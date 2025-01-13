# frozen_string_literal: true

module OnlineMigrations
  module BackgroundMigrations
    # Class responsible for scheduling background migrations.
    #
    # It selects a single runnable background migration and runs it one step (one batch) at a time.
    # A migration is considered runnable if it is not completed and the time interval between
    # successive runs has passed.
    #
    # Scheduler should be configured to run periodically, for example, via cron.
    # @example Run via whenever
    #   # add this to schedule.rb
    #   every 1.minute do
    #     runner "OnlineMigrations.run_background_migrations"
    #   end
    #
    class Scheduler
      def self.run
        new.run
      end

      # Runs Scheduler
      def run
        active_migrations = Migration.runnable.active.queue_order
        runnable_migration = active_migrations.select(&:interval_elapsed?).first

        if runnable_migration
          runner = MigrationRunner.new(runnable_migration)

          try_with_lock do
            runner.run_migration_job
          end
        end
      end

      private
        def try_with_lock(&block)
          lock = AdvisoryLock.new(name: "online_migrations_data_scheduler")
          lock.try_with_lock(&block)
        end
    end
  end
end
