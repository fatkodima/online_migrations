# frozen_string_literal: true

module OnlineMigrations
  module BackgroundSchemaMigrations
    # Class representing background schema migration.
    #
    # @note The records of this class should not be created manually, but via
    #   `enqueue_background_schema_migration` helper inside migrations.
    #
    class Migration < ApplicationRecord
      include ShardAware

      STATUSES = [
        "enqueued",    # The migration has been enqueued by the user.
        "running",     # The migration is being performed by a migration executor.
        "errored",     # The migration raised an error during last run.
        "failed",      # The migration raises an error when running and retry attempts exceeded.
        "succeeded",   # The migration finished without error.
        "cancelled",   # The migration was cancelled by the user.
      ]

      MAX_IDENTIFIER_LENGTH = 63

      self.table_name = :background_schema_migrations

      scope :queue_order, -> { order(created_at: :asc) }
      scope :active, -> { where(status: [:enqueued, :running, :errored]) }

      scope :stuck, -> do
        active.where(<<~SQL)
          updated_at <= NOW() - interval '1 second' * (COALESCE(statement_timeout, 60*60*24) + 60*10)
        SQL
      end

      scope :retriable, -> do
        stuck_sql = connection.unprepared_statement { stuck.to_sql }

        from(Arel.sql(<<~SQL))
          (
            (SELECT * FROM background_schema_migrations WHERE status = 'errored')
            UNION
            (#{stuck_sql})
          ) AS #{table_name}
        SQL
      end

      alias_attribute :name, :migration_name

      enum :status, STATUSES.index_with(&:to_s)

      validates :table_name, presence: true, length: { maximum: MAX_IDENTIFIER_LENGTH }
      validates :definition, presence: true
      validates :migration_name, presence: true, uniqueness: {
        scope: [:connection_class_name, :shard],
        message: ->(object, data) do
          message = "(#{data[:value]}) has already been taken."
          if object.index_addition?
            message += " Consider enqueuing index creation with a different index name via a `:name` option."
          end
          message
        end,
      }

      validate :validate_table_exists
      validates_with MigrationStatusValidator, on: :update

      before_validation :set_defaults

      # Returns whether the migration is completed, which is defined as
      # having a status of succeeded, failed, or cancelled.
      #
      # @return [Boolean] whether the migration is completed.
      #
      def completed?
        succeeded? || failed? || cancelled?
      end

      # Returns whether the migration is active, which is defined as
      # having a status of enqueued, or running.
      #
      # @return [Boolean] whether the migration is active.
      #
      def active?
        enqueued? || running?
      end

      alias cancel cancelled!

      # Returns whether this migration is pausable.
      #
      def pausable?
        false
      end

      # Dummy method to support the same interface as background data migrations.
      #
      # @return [nil]
      #
      def progress
      end

      # Whether the migration is considered stuck (is running for some configured time).
      #
      def stuck?
        stuck_timeout = (statement_timeout || 1.day) + 10.minutes
        running? && updated_at <= stuck_timeout.seconds.ago
      end

      # Mark this migration as ready to be processed again.
      #
      # This is used to manually retrying failed migrations.
      #
      def retry
        if failed?
          update!(
            status: :enqueued,
            attempts: 0,
            started_at: nil,
            finished_at: nil,
            error_class: nil,
            error_message: nil,
            backtrace: nil
          )

          true
        else
          false
        end
      end

      def index_addition?
        definition.match?(/create (unique )?index/i)
      end

      # @private
      def attempts_exceeded?
        attempts >= max_attempts
      end

      # @private
      def run
        on_shard_if_present do
          connection = connection_class.connection

          connection.with_lock_retries do
            statement_timeout = self.statement_timeout || OnlineMigrations.config.statement_timeout

            with_statement_timeout(connection, statement_timeout) do
              if index_addition?
                index = connection.indexes(table_name).find { |i| i.name == name }
                if index
                  if index.valid?
                    return
                  else
                    connection.remove_index(table_name, name: name, algorithm: :concurrently)
                  end
                end
              end

              connection.execute(definition)

              # Outdated statistics + a new index can hurt performance of existing queries.
              if OnlineMigrations.config.auto_analyze
                connection.execute("ANALYZE #{table_name}")
              end
            end
          end
        end
      end

      private
        def validate_table_exists
          # Skip this validation if we have invalid connection class name.
          return if errors.include?(:connection_class_name)

          on_shard_if_present do
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
