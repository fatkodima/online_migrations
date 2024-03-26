# frozen_string_literal: true

module OnlineMigrations
  module BackgroundSchemaMigrations
    # Class responsible for scheduling background schema migrations.
    # It selects a single migration and runs it if there is no currently running migration.
    #
    # Scheduler should be configured to run periodically, for example, via cron.
    # @example Run via whenever
    #   # add this to schedule.rb
    #   every 1.minute do
    #     runner "OnlineMigrations.run_background_schema_migrations"
    #   end
    #
    class Scheduler
      def self.run
        new.run
      end

      # Runs Scheduler
      def run
        migration = Migration.runnable.enqueued.queue_order.first || Migration.retriable.queue_order.first
        if migration
          runner = MigrationRunner.new(migration)
          runner.run
        end
      end
    end
  end
end
