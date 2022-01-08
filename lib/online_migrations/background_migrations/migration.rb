# frozen_string_literal: true

module OnlineMigrations
  module BackgroundMigrations
    class Migration < ActiveRecord::Base
      STATUSES = [
        :enqueued,    # The migration has been enqueued by the user.
        :running,     # The migration is being performed by a migration executor.
        :paused,      # The migration was paused in the middle of the run by the user.
        :finishing,   # The migration is being manually finishing inline by the user.
        :failed,      # The migration raises an exception when running.
        :succeeded,   # The migration finished without error.
      ]

      self.table_name = :background_migrations

      scope :queue_order, -> { order(created_at: :asc) }
      scope :active, -> { where(status: [statuses[:enqueued], statuses[:running]]) }
      scope :for_migration_name, ->(migration_name) { where(migration_name: normalize_migration_name(migration_name)) }
      scope :for_configuration, ->(migration_name, arguments) do
        for_migration_name(migration_name).where("arguments = ?", arguments.to_json)
      end

      enum status: STATUSES.map { |status| [status, status.to_s] }.to_h

      has_many :migration_jobs

      validates :migration_name, :batch_column_name, presence: true

      validates :batch_pause, :min_value, :max_value, :batch_size, :sub_batch_size,
                  presence: true, numericality: { greater_than: 0 }

      validates :sub_batch_pause_ms, presence: true, numericality: { greater_than_or_equal_to: 0 }
      validates :rows_count, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
      validates :arguments, uniqueness: { scope: :migration_name }

      validate :validate_batch_column_values
      validate :validate_batch_sizes

      validates_with MigrationStatusValidator, on: :update

      before_validation :set_defaults

      # @private
      def self.normalize_migration_name(migration_name)
        namespace = ::OnlineMigrations.config.background_migrations.migrations_module
        migration_name.sub(/^(::)?#{namespace}::/, "")
      end

      def migration_name=(class_name)
        write_attribute(:migration_name, self.class.normalize_migration_name(class_name))
      end

      def completed?
        succeeded? || failed?
      end

      def last_job
        migration_jobs.order(max_value: :desc).first
      end

      def last_completed_job
        migration_jobs.completed.order(finished_at: :desc).first
      end

      # Returns the progress of the background migration.
      #
      # @return [Float, nil]
      #   - when background migration is configured to not to track progress, returns `nil`
      #   - otherwise returns value in range of 0.0 and 1.0
      #
      def progress
        if succeeded?
          1.0
        elsif rows_count
          jobs_rows_count = migration_jobs.succeeded.sum(:batch_size)
          # The last migration job may need to process the amount of rows
          # less than the batch size, so we can get a value > 1.0.
          [jobs_rows_count.to_f / rows_count, 1.0].min
        end
      end

      def migration_class
        BackgroundMigration.named(migration_name)
      end

      def migration_object
        @migration_object ||= migration_class.new(*arguments)
      end

      def migration_relation
        migration_object.relation
      end

      # Returns whether the interval between previous step run has passed.
      # @return [Boolean]
      #
      def interval_elapsed?
        if migration_jobs.running.exists?
          false
        elsif (job = last_completed_job)
          job.finished_at + batch_pause <= Time.current
        else
          true
        end
      end

      # Manually retry failed jobs.
      #
      # This method marks failed jobs as ready to be processed again, and
      # they will be picked up on the next Scheduler run.
      #
      def retry_failed_jobs
        iterator = BatchIterator.new(migration_jobs.failed)
        iterator.each_batch(of: 100) do |batch|
          transaction do
            batch.each(&:retry)
            enqueued!
          end
        end
      end

      # @private
      def next_batch_range
        iterator = BatchIterator.new(migration_relation)
        batch_range = nil

        # rubocop:disable Lint/UnreachableLoop
        iterator.each_batch(of: batch_size, column: batch_column_name, start: next_min_value) do |relation|
          if Utils.ar_version <= 4.2
            # ActiveRecord <= 4.2 does not support pluck with Arel nodes
            quoted_column = self.class.connection.quote_column_name(batch_column_name)
            batch_range = relation.pluck("MIN(#{quoted_column}), MAX(#{quoted_column})").first
          else
            min = relation.arel_table[batch_column_name].minimum
            max = relation.arel_table[batch_column_name].maximum

            batch_range = relation.pluck(min, max).first
          end
          break
        end
        # rubocop:enable Lint/UnreachableLoop

        return if batch_range.nil?

        min_value, max_value = batch_range
        return if min_value > self.max_value

        max_value = [max_value, self.max_value].min

        [min_value, max_value]
      end

      private
        def validate_batch_column_values
          if max_value.to_i < min_value.to_i
            errors.add(:base, "max_value should be greater than or equal to min_value")
          end
        end

        def validate_batch_sizes
          if sub_batch_size.to_i > batch_size.to_i
            errors.add(:base, "sub_batch_size should be smaller than or equal to batch_size")
          end
        end

        def set_defaults
          if migration_relation.is_a?(ActiveRecord::Relation)
            self.batch_column_name  ||= migration_relation.primary_key
            self.min_value          ||= migration_relation.minimum(batch_column_name)
            self.max_value          ||= migration_relation.maximum(batch_column_name)

            count = migration_object.count
            self.rows_count = count if count != :no_count
          end

          config = ::OnlineMigrations.config.background_migrations
          self.batch_size           ||= config.batch_size
          self.sub_batch_size       ||= config.sub_batch_size
          self.batch_pause          ||= config.batch_pause
          self.sub_batch_pause_ms   ||= config.sub_batch_pause_ms
          self.batch_max_attempts   ||= config.batch_max_attempts

          # This can be the case when run in development on empty tables
          if min_value.nil?
            # integer IDs minimum value is 1
            self.min_value = self.max_value = 1
          end
        end

        def next_min_value
          if last_job
            last_job.max_value.next
          else
            min_value
          end
        end
    end
  end
end
