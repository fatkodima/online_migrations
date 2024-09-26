# frozen_string_literal: true

module OnlineMigrations
  module BackgroundMigrations
    # Runs single background migration.
    class MigrationRunner
      attr_reader :migration

      def initialize(migration)
        @migration = migration
      end

      # Runs one background migration job.
      def run_migration_job
        raise "Should not be called on a composite (with sharding) migration" if migration.composite?
        return if migration.cancelled? || migration.succeeded?

        mark_as_running if migration.enqueued?
        migration_payload = notifications_payload(migration)

        if !migration.migration_jobs.exists?
          ActiveSupport::Notifications.instrument("started.background_migrations", migration_payload)
        end

        if should_throttle?
          ActiveSupport::Notifications.instrument("throttled.background_migrations", migration_payload)
          return
        end

        next_migration_job = find_or_create_next_migration_job

        if next_migration_job
          job_runner = MigrationJobRunner.new(next_migration_job)
          job_runner.run
        elsif !migration.migration_jobs.active.exists?
          if migration.migration_jobs.failed.exists?
            migration.failed!
          else
            migration.succeeded!
          end

          ActiveSupport::Notifications.instrument("completed.background_migrations", migration_payload)

          complete_parent_if_needed(migration) if migration.parent.present?
        end

        next_migration_job
      end

      # Runs the background migration until completion.
      #
      # @note This method should not be used in production environments
      #
      def run_all_migration_jobs
        run_inline = OnlineMigrations.config.run_background_migrations_inline
        if run_inline && !run_inline.call
          raise "This method is not intended for use in production environments"
        end

        return if migration.completed? || migration.cancelled?

        mark_as_running

        if migration.composite?
          migration.children.each do |child_migration|
            runner = self.class.new(child_migration)
            runner.run_all_migration_jobs
          end
        else
          while migration.running?
            run_migration_job
          end
        end
      end

      # Finishes the background migration.
      #
      # Keep running until the migration is finished.
      #
      def finish
        return if migration.completed? || migration.cancelled?

        if migration.composite?
          migration.children.each do |child_migration|
            runner = self.class.new(child_migration)
            runner.finish
          end
        else
          # Mark is as finishing to avoid being picked up
          # by the background migrations scheduler.
          migration.finishing!
          migration.reset_failed_jobs_attempts

          while migration.finishing?
            run_migration_job
          end
        end
      end

      private
        def mark_as_running
          Migration.transaction do
            migration.running!
            migration.parent.running! if migration.parent && migration.parent.enqueued?
          end
        end

        def should_throttle?
          ::OnlineMigrations.config.throttler.call
        end

        def find_or_create_next_migration_job
          min_value, max_value = migration.next_batch_range

          if min_value && max_value
            create_migration_job!(min_value, max_value)
          else
            migration.migration_jobs.enqueued.first || migration.migration_jobs.retriable.first
          end
        end

        def create_migration_job!(min_value, max_value)
          migration.migration_jobs.create!(
            min_value: min_value,
            max_value: max_value
          )
        end

        def complete_parent_if_needed(migration)
          parent = migration.parent
          completed = false

          parent.with_lock do
            children = parent.children.select(:status)
            if children.all?(&:succeeded?)
              parent.succeeded!
              completed = true
            elsif children.any?(&:failed?)
              parent.failed!
              completed = true
            end
          end

          if completed
            ActiveSupport::Notifications.instrument("completed.background_migrations", notifications_payload(migration))
          end
        end

        def notifications_payload(migration)
          { background_migration: migration }
        end
    end
  end
end
