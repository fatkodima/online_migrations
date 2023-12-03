# frozen_string_literal: true

module OnlineMigrations
  module BackgroundMigrations
    # Class responsible for scheduling background migrations.
    # It selects runnable background migrations and runs them one step (one batch) at a time.
    # A migration is considered runnable if it is not completed and the time interval between
    #   successive runs has passed.
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
        runnable_migrations = active_migrations.select(&:interval_elapsed?)

        runnable_migrations.each do |migration|
          run_migration_job(migration)
        end
      end

      private
        def run_migration_job(migration)
          runner = MigrationRunner.new(migration)
          runner.run_migration_job
        end
    end
  end
end
