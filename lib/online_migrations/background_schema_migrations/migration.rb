# frozen_string_literal: true

module OnlineMigrations
  module BackgroundSchemaMigrations
    # Class representing background schema migration.
    #
    # @note The records of this class should not be created manually, but via
    #   `enqueue_background_schema_migration` helper inside migrations.
    #
    class Migration < ApplicationRecord
      STATUSES = [
        :enqueued,    # The migration has been enqueued by the user.
        :running,     # The migration is being performed by a migration executor.
        :failed,      # The migration raises an exception when running.
        :succeeded,   # The migration finished without error.
      ]

      MAX_IDENTIFIER_LENGTH = 63

      self.table_name = :background_schema_migrations

      scope :queue_order, -> { order(created_at: :asc) }
      scope :parents, -> { where(parent_id: nil) }
      scope :runnable, -> { where(composite: false) }
      scope :active, -> { where(status: [statuses[:enqueued], statuses[:running]]) }
      scope :except_succeeded, -> { where.not(status: :succeeded) }

      scope :stuck, -> do
        runnable.active.where(<<~SQL)
          updated_at <= NOW() - interval '1 second' * (COALESCE(statement_timeout, 60*60*24) + 60*10)
        SQL
      end

      scope :retriable, -> do
        failed_retriable = runnable.failed.where("attempts < max_attempts")

        stuck_sql             = connection.unprepared_statement { stuck.to_sql }
        failed_retriable_sql  = connection.unprepared_statement { failed_retriable.to_sql }

        from(Arel.sql(<<~SQL))
          (
            (#{failed_retriable_sql})
            UNION
            (#{stuck_sql})
          ) AS #{table_name}
        SQL
      end

      alias_attribute :name, :migration_name

      # Avoid deprecation warnings.
      if Utils.ar_version >= 7
        enum :status, STATUSES.index_with(&:to_s)
      else
        enum status: STATUSES.index_with(&:to_s)
      end

      belongs_to :parent, class_name: name, optional: true
      has_many :children, class_name: name, foreign_key: :parent_id

      validates :table_name, presence: true, length: { maximum: MAX_IDENTIFIER_LENGTH }
      validates :definition, presence: true
      validates :migration_name, presence: true, uniqueness: {
        scope: :shard,
        message: ->(object, data) do
          message = "(#{data[:value]}) has already been taken."
          if object.index_addition?
            message += " Consider enqueuing index creation with a different index name via a `:name` option."
          end
          message
        end,
      }

      validate :validate_children_statuses, if: -> { composite? && status_changed? }
      validate :validate_connection_class, if: :connection_class_name?
      validate :validate_table_exists
      validates_with MigrationStatusValidator, on: :update

      before_validation :set_defaults

      def completed?
        succeeded? || failed?
      end

      # Returns the progress of the background schema migration.
      #
      # @return [Float] value in range from 0.0 to 100.0
      #
      def progress
        if succeeded?
          100.0
        elsif composite?
          progresses = children.map(&:progress)
          # There should not be composite migrations without children,
          # but children may be deleted for some reason, so we need to
          # make a check to avoid 0 division error.
          if progresses.any?
            (progresses.sum.to_f / progresses.size).round(2)
          else
            0.0
          end
        else
          0.0
        end
      end

      # Mark this migration as ready to be processed again.
      #
      # This is used to manually retrying failed migrations.
      #
      def retry
        if composite?
          children.failed.each(&:retry)
        elsif failed?
          update!(
            status: self.class.statuses[:enqueued],
            attempts: 0,
            started_at: nil,
            finished_at: nil,
            error_class: nil,
            error_message: nil,
            backtrace: nil
          )
        end
      end

      def index_addition?
        definition.match?(/create (unique )?index/i)
      end

      # @private
      def connection_class
        if connection_class_name && (klass = connection_class_name.safe_constantize)
          Utils.find_connection_class(klass)
        else
          ActiveRecord::Base
        end
      end

      # @private
      def attempts_exceeded?
        attempts >= max_attempts
      end

      # @private
      def run
        on_shard do
          connection = connection_class.connection

          connection.with_lock_retries do
            statement_timeout = self.statement_timeout || OnlineMigrations.config.statement_timeout

            with_statement_timeout(connection, statement_timeout) do
              if index_addition?
                index = connection.indexes(table_name).find { |i| i.name == name }
                if index
                  # Use index validity from https://github.com/rails/rails/pull/45160
                  # when switching to ActiveRecord >= 7.1.
                  schema = connection.send(:__schema_for_table, table_name)
                  if connection.send(:__index_valid?, name, schema: schema)
                    return
                  else
                    connection.remove_index(table_name, name: name)
                  end
                end
              end

              connection.execute(definition)
            end
          end
        end
      end

      private
        def validate_children_statuses
          if composite?
            if succeeded? && children.except_succeeded.exists?
              errors.add(:base, "all child migrations must be succeeded")
            elsif failed? && !children.failed.exists?
              errors.add(:base, "at least one child migration must be failed")
            end
          end
        end

        def validate_connection_class
          klass = connection_class_name.safe_constantize
          if !(klass < ActiveRecord::Base)
            errors.add(:connection_class_name, "is not an ActiveRecord::Base child class")
          end
        end

        def validate_table_exists
          # Skip this validation if we have invalid connection class name.
          return if errors.include?(:connection_class_name)

          on_shard do
            if !connection_class.connection.table_exists?(table_name)
              errors.add(:table_name, "'#{table_name}' does not exist")
            end
          end
        end

        def set_defaults
          config = ::OnlineMigrations.config.background_schema_migrations
          self.max_attempts ||= config.max_attempts
          self.statement_timeout ||= config.statement_timeout
        end

        def on_shard(&block)
          shard = (self.shard || connection_class.default_shard).to_sym
          connection_class.connected_to(shard: shard, role: :writing, &block)
        end

        def with_statement_timeout(connection, timeout)
          return yield if timeout.nil?

          prev_value = connection.select_value("SHOW statement_timeout")
          connection.execute("SET statement_timeout TO #{connection.quote(timeout.in_milliseconds)}")
          yield
        ensure
          connection.execute("SET statement_timeout TO #{connection.quote(prev_value)}")
        end
    end
  end
end
