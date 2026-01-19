# frozen_string_literal: true

module OnlineMigrations
  module BackgroundDataMigrations
    # Class responsible for scheduling background data migrations.
    #
    # Scheduler should be configured to run periodically, for example, via cron.
    #
    # @example Run via whenever
    #   # add this to schedule.rb
    #   every 1.minute do
    #     runner "OnlineMigrations.run_background_data_migrations"
    #   end
    #
    # @example Specific shard
    #   every 1.minute do
    #     runner "OnlineMigrations.run_background_data_migrations(shard: :shard_two)"
    #   end
    #
    # @example Custom concurrency
    #   every 1.minute do
    #     # Allow to run 2 data migrations in parallel.
    #     runner "OnlineMigrations.run_background_data_migrations(concurrency: 2)"
    #   end
    #
    class Scheduler
      def self.run(**options)
        new.run(**options)
      end

      # Runs Scheduler
      def run(shard: nil, concurrency: 1)
        relation = Migration.queue_order
        relation = relation.where(shard: shard) if shard

        with_lock do
          stuck_migrations, active_migrations = relation.running.partition(&:stuck?)
          runnable_migrations = relation.pending + stuck_migrations

          # Ensure no more than 'concurrency' migrations are running at the same time.
          remaining_to_enqueue = concurrency - active_migrations.count
          if remaining_to_enqueue > 0
            migrations_to_enqueue = runnable_migrations.take(remaining_to_enqueue)
            migrations_to_enqueue.each do |migration|
              enqueue_migration(migration)
            end
          end
        end

        true
      end

      private
        def with_lock(&block)
          # Don't lock the whole table if we can lock only a single record (must be always the same).
          first_record = Migration.queue_order.first
          if first_record
            first_record.with_lock(&block)
          else
            Migration.transaction do
              Migration.connection.execute("LOCK #{Migration.table_name} IN ACCESS EXCLUSIVE MODE")
              yield
            end
          end
        end

        def enqueue_migration(migration)
          job = OnlineMigrations.config.background_data_migrations.job
          job_class = job.constantize
          migration.update!(status: :enqueued)

          jid = job_class.perform_async(migration.id)
          if jid
            migration.update!(jid: jid)
          end
        end
    end
  end
end
