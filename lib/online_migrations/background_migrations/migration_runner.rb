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
        migration.running! if migration.enqueued?
        migration_payload = { background_migration: migration }

        if !migration.migration_jobs.exists?
          ActiveSupport::Notifications.instrument("started.background_migrations", migration_payload)
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
        end

        next_migration_job
      end

      # Runs the background migration until completion.
      #
      # @note This method should not be used in production environments
      #
      def run_all_migration_jobs
        raise "This method is not intended for use in production environments" if !Utils.developer_env?
        return if migration.completed?

        migration.running!

        while migration.running?
          run_migration_job
        end
      end

      # Finishes the background migration.
      #
      # Keep running until the migration is finished.
      #
      def finish
        return if migration.completed?

        # Mark is as finishing to avoid being picked up
        # by the background migrations scheduler.
        migration.finishing!

        while migration.finishing?
          run_migration_job
        end
      end

      private
        def find_or_create_next_migration_job
          if (min_value, max_value = migration.next_batch_range)
            create_migration_job!(min_value, max_value)
          else
            migration.migration_jobs.retriable.first
          end
        end

        def create_migration_job!(min_value, max_value)
          migration.migration_jobs.create!(
            min_value: min_value,
            max_value: max_value
          )
        end
    end
  end
end
