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
    #
    # @example Run via whenever
    #   # add this to schedule.rb
    #   every 1.minute do
    #     runner "OnlineMigrations.run_background_data_migrations"
    #   end
    #
    # @example Run via whenever (specific shard)
    #   every 1.minute do
    #     runner "OnlineMigrations.run_background_data_migrations(shard: :shard_two)"
    #   end
    #
    class Scheduler
      def self.run(shard: nil)
        new.run(shard: shard)
      end

      # Runs Scheduler
      def run(shard: nil)
        active_migrations = Migration.runnable.active.queue_order
        active_migrations = active_migrations.where(shard: shard) if shard
        runnable_migration = active_migrations.select(&:interval_elapsed?).first

        if runnable_migration
          runner = MigrationRunner.new(runnable_migration)

          if shard
            runnable_migration.on_shard do
              connection = runnable_migration.migration_model.connection
              try_with_lock(connection: connection) do
                runner.run_migration_job
              end
            end
          else
            try_with_lock do
              runner.run_migration_job
            end
          end
        end
      end

      private
        def try_with_lock(**options, &block)
          lock = AdvisoryLock.new(name: "online_migrations_data_scheduler", **options)
          lock.try_with_lock(&block)
        end
    end
  end
end
