# frozen_string_literal: true

module OnlineMigrations
  module BackgroundSchemaMigrations
    # Class responsible for scheduling background schema migrations.
    # It selects a single migration and runs it if there is no currently
    # running migration on the same table.
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
        migration = find_migration
        if migration
          runner = MigrationRunner.new(migration)

          try_with_lock do
            runner.run
          end
        end
      end

      private
        def find_migration
          active_migrations = Migration.running.reject(&:stuck?)
          runnable_migrations = Migration.runnable.enqueued.queue_order.to_a + Migration.retriable.queue_order.to_a

          runnable_migrations.find do |runnable_migration|
            active_migrations.none? do |active_migration|
              active_migration.connection_class_name == runnable_migration.connection_class_name &&
                active_migration.shard == runnable_migration.shard &&
                active_migration.table_name == runnable_migration.table_name
            end
          end
        end

        def try_with_lock(&block)
          lock = AdvisoryLock.new(name: "online_migrations_schema_scheduler")
          lock.try_with_lock(&block)
        end
    end
  end
end
