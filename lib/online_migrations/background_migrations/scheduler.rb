# frozen_string_literal: true

module OnlineMigrations
  module BackgroundMigrations
    # Class responsible for scheduling background migrations.
    # It selects runnable background migrations and runs them one step (one batch) at a time.
    # A migration is considered runnable if it is not completed and time the interval between
    #   successive runs has passed.
    # Scheduler ensures (via advisory locks) that at most one background migration at a time is running per database.
    #
    # Scheduler should be run via some kind of periodical means, for example, cron.
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
        active_migrations = Migration.active.queue_order
        runnable_migrations = active_migrations.select(&:interval_elapsed?)

        runnable_migrations.each do |migration|
          connection = migration.migration_relation.connection

          with_exclusive_lock(connection) do
            run_migration_job(migration)
          end
        end
      end

      private
        def with_exclusive_lock(connection, &block)
          lock = AdvisoryLock.new(name: "online_migrations_scheduler", connection: connection)
          lock.with_lock(&block)
        end

        def run_migration_job(migration)
          runner = MigrationRunner.new(migration)
          runner.run_migration_job
        end
    end
  end
end
