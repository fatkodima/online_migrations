# frozen_string_literal: true

module OnlineMigrations
  module BackgroundSchemaMigrations
    # Class responsible for scheduling background schema migrations.
    # It selects a single migration and runs it if there is no currently
    # running migration on the same table.
    #
    # Scheduler should be configured to run periodically, for example, via cron.
    #
    # @example Run via whenever
    #   # add this to schedule.rb
    #   every 1.minute do
    #     runner "OnlineMigrations.run_background_schema_migrations"
    #   end
    #
    # @example Run via whenever (specific shard)
    #   every 1.minute do
    #     runner "OnlineMigrations.run_background_schema_migrations(shard: :shard_two)"
    #   end
    #
    class Scheduler
      def self.run(shard: nil)
        new.run(shard: shard)
      end

      # Runs Scheduler
      def run(shard: nil)
        migration = find_migration(shard)
        if migration
          runner = MigrationRunner.new(migration)

          if shard
            migration.on_shard do
              connection = migration.connection_class.connection
              try_with_lock(connection: connection) do
                runner.run
              end
            end
          else
            try_with_lock do
              runner.run
            end
          end
        end
      end

      private
        def find_migration(shard)
          active_migrations = Migration.running.reject(&:stuck?)
          runnable_migrations = Migration.runnable.enqueued.queue_order.to_a + Migration.retriable.queue_order.to_a

          if shard
            runnable_migrations = runnable_migrations.select { |migration| migration.shard.to_s == shard.to_s }
          end

          runnable_migrations.find do |runnable_migration|
            active_migrations.none? do |active_migration|
              active_migration.connection_class_name == runnable_migration.connection_class_name &&
                active_migration.shard == runnable_migration.shard &&
                active_migration.table_name == runnable_migration.table_name
            end
          end
        end

        def try_with_lock(**options, &block)
          lock = AdvisoryLock.new(name: "online_migrations_schema_scheduler", **options)
          lock.try_with_lock(&block)
        end
    end
  end
end
