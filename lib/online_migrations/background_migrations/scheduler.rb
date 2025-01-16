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
      def self.run(**options)
        new.run(**options)
      end

      # Runs Scheduler
      def run(**options)
        active_migrations = Migration.runnable.active.queue_order
        active_migrations = active_migrations.where(shard: options[:shard]) if options.key?(:shard)
        runnable_migration = active_migrations.select(&:interval_elapsed?).first

        if runnable_migration
          runner = MigrationRunner.new(runnable_migration)
          runner.run_migration_job
        end
      end
    end
  end
end
