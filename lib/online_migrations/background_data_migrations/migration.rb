# frozen_string_literal: true

module OnlineMigrations
  module BackgroundDataMigrations
    # Class representing background data migration.
    #
    # @note The records of this class should not be created manually, but via
    #   `enqueue_background_data_migration` helper inside migrations.
    #
    class Migration < ApplicationRecord
      include ShardAware

      STATUSES = [
        "pending",     # The migration has been created by the user.
        "enqueued",    # The migration has been enqueued by the scheduler.
        "running",     # The migration is being performed by a migration executor.
        "pausing",     # The migration has been told to pause but is finishing work.
        "paused",      # The migration was paused in the middle of the run by the user.
        "errored",     # The migration raised an error during last run.
        "failed",      # The migration raises an error when running and retry attempts exceeded.
        "succeeded",   # The migration finished without error.
        "cancelling",  # The migration has been told to cancel but is finishing work.
        "cancelled",   # The migration was cancelled by the user.
        "delayed",     # The migration was created, but waiting approval from the user to start running.
      ]

      COMPLETED_STATUSES = ["succeeded", "failed", "cancelled"]

      ACTIVE_STATUSES = [
        "pending",
        "enqueued",
        "running",
        "failed",
        "pausing",
        "paused",
        "cancelling",
      ]

      STOPPING_STATUSES = ["pausing", "cancelling", "cancelled"]

      self.table_name = :background_data_migrations
      self.ignored_columns += ["parent_id", "batch_column_name", "min_value", "max_value", "rows_count",
                               "batch_size", "sub_batch_size", "batch_pause", "sub_batch_pause_ms", "composite"]

      scope :queue_order, -> { order(created_at: :asc) }
      scope :for_migration_name, ->(migration_name) { where(migration_name: normalize_migration_name(migration_name)) }
      scope :for_configuration, ->(migration_name, arguments) do
        for_migration_name(migration_name).where("arguments = ?", arguments.to_json)
      end

      alias_attribute :name, :migration_name

      enum :status, STATUSES.index_with(&:to_s)

      validates :migration_name, presence: true
      validates :arguments, uniqueness: { scope: [:migration_name, :shard] }

      validates_with MigrationStatusValidator, on: :update

      before_save :set_defaults
      after_save :instrument_status_change, if: :status_previously_changed?

      # @private
      def self.normalize_migration_name(migration_name)
        namespace = ::OnlineMigrations.config.background_data_migrations.migrations_module
        migration_name.sub(/^(::)?#{namespace}::/, "")
      end

      def migration_name=(class_name)
        class_name = class_name.name if class_name.is_a?(Class)
        write_attribute(:migration_name, self.class.normalize_migration_name(class_name))
      end
      alias name= migration_name=

      # Returns whether the migration has been started, which is indicated by the
      # started_at timestamp being present.
      #
      # @return [Boolean] whether the migration was started.
      #
      def started?
        started_at.present?
      end

      # Returns whether the migration is completed, which is defined as
      # having a status of succeeded, failed, or cancelled.
      #
      # @return [Boolean] whether the migration is completed.
      #
      def completed?
        COMPLETED_STATUSES.include?(status)
      end

      # Returns whether the migration is active, which is defined as
      # having a status of pending, enqueued, running, pausing, paused, or cancelling.
      #
      # @return [Boolean] whether the migration is active.
      #
      def active?
        ACTIVE_STATUSES.include?(status)
      end

      # Returns whether the migration is stopping, which is defined as having a status
      # of pausing or cancelling. The status of cancelled is also considered
      # stopping since a migration can be cancelled while its job still exists in the
      # queue, and we want to handle it the same way as a cancelling run.
      #
      # @return [Boolean] whether the migration is stopping.
      #
      def stopping?
        STOPPING_STATUSES.include?(status)
      end

      # Returns whether a migration is stuck, which is defined as having a status of
      # running, cancelling or pausing, and not having been updated in the last 5 minutes.
      #
      # @return [Boolean] whether the migration is stuck.
      #
      def stuck?
        stuck_timeout = OnlineMigrations.config.background_data_migrations.stuck_timeout
        (running? || cancelling? || pausing?) && updated_at <= stuck_timeout.ago
      end

      # @private
      def start
        if enqueued?
          update!(status: :running, started_at: Time.current)
          data_migration.after_start
          true
        else
          false
        end
      end

      # Enqueue this data migration. No-op if migration is not delayed.
      #
      # @return [Boolean] whether this data migration was enqueued.
      #
      def enqueue
        if delayed?
          pending!
          true
        else
          false
        end
      end

      # Cancel this data migration. No-op if migration is completed.
      #
      # @return [Boolean] whether this data migration was cancelled.
      #
      def cancel
        return false if completed?

        if paused? || delayed? || stuck?
          update!(status: :cancelled, finished_at: Time.current)
        elsif pending? || enqueued? || errored?
          cancelled!
        else
          cancelling!
        end

        true
      end

      # Pause this data migration. No-op if migration is completed.
      #
      # @return [Boolean] whether this data migration was paused.
      #
      def pause
        return false if completed?

        if pending? || enqueued? || delayed? || stuck? || errored?
          paused!
        else
          pausing!
        end

        true
      end

      # Resume this data migration. No-op if migration is not paused.
      #
      # @return [Boolean] whether this data migration was resumed.
      #
      def resume
        if paused?
          pending!
          true
        else
          false
        end
      end

      # @private
      def stop
        return false if completed?

        if cancelling?
          update!(status: :cancelled, finished_at: Time.current)
          data_migration.after_cancel
          data_migration.after_complete
        elsif pausing?
          paused!
          data_migration.after_pause
        end

        data_migration.after_stop
        true
      end

      # @private
      def complete
        return false if completed?

        if running?
          update!(status: :succeeded, finished_at: Time.current)
          data_migration.after_complete
        elsif pausing?
          update!(status: :paused, finished_at: Time.current)
        elsif cancelling?
          update!(status: :cancelled, finished_at: Time.current)
          data_migration.after_complete
        end

        true
      end

      # @private
      def persist_progress(cursor, number_of_ticks, duration)
        update!(
          cursor: cursor,
          tick_count: tick_count + number_of_ticks,
          time_running: time_running + duration
        )
      end

      # @private
      def persist_error(error, attempt)
        backtrace = error.backtrace
        backtrace_cleaner = OnlineMigrations.config.backtrace_cleaner
        backtrace = backtrace_cleaner.clean(backtrace) if backtrace_cleaner
        status = attempt >= max_attempts ? :failed : :errored

        update!(
          status: status,
          finished_at: Time.current,
          error_class: error.class.name,
          error_message: error.message,
          backtrace: backtrace
        )
      end

      # Returns whether this migration is pausable.
      #
      def pausable?
        true
      end

      # Returns the progress of the data migration.
      #
      # @return [Float, nil]
      #   - when background migration is configured to not track progress, returns `nil`
      #   - otherwise returns value in range from 0.0 to 100.0
      #
      def progress
        if succeeded?
          100.0
        elsif tick_total == 0
          0.0
        elsif tick_total
          ([tick_count.to_f / tick_total, 1.0].min * 100)
        end
      end

      # Returns data migration associated with this migration.
      #
      # @return [OnlineMigrations::DataMigration]
      #
      def data_migration
        @data_migration ||= begin
          klass = DataMigration.named(migration_name)
          klass.new(*arguments)
        end
      end

      # Mark this migration as ready to be processed again.
      #
      # This method marks failed migrations as ready to be processed again, and
      # they will be picked up on the next Scheduler run.
      #
      def retry
        if failed?
          update!(
            status: :pending,
            started_at: nil,
            finished_at: nil,
            error_class: nil,
            error_message: nil,
            backtrace: nil,
            jid: nil
          )
          true
        else
          false
        end
      end

      private
        def set_defaults
          config = ::OnlineMigrations.config.background_data_migrations
          self.max_attempts ||= config.max_attempts
          self.tick_total ||= on_shard_if_present do
            data_migration.count
          end

          self.iteration_pause ||= config.iteration_pause
        end

        def instrument_status_change
          payload = { migration: self }
          if running?
            ActiveSupport::Notifications.instrument("started.background_data_migrations", payload)
          elsif succeeded?
            ActiveSupport::Notifications.instrument("completed.background_data_migrations", payload)
          end
        end
    end
  end
end
