# frozen_string_literal: true

module OnlineMigrations
  module BackgroundMigrations
    module MigrationHelpers
      # Creates a background migration for the given job class name.
      #
      # A background migration runs one job at a time, computing the bounds of the next batch
      # based on the current migration settings and the previous batch bounds. Each job's execution status
      # is tracked in the database as the migration runs.
      #
      # @param migration_name [String] Background migration job class name
      # @param arguments [Array] Extra arguments to pass to the job instance when the migration runs
      # @option options [Symbol, String] :batch_column_name (primary key) Column name the migration will batch over
      # @option options [Integer] :min_value Value in the column the batching will begin at,
      #     defaults to `SELECT MIN(batch_column_name)`
      # @option options [Integer] :max_value Value in the column the batching will end at,
      #     defaults to `SELECT MAX(batch_column_name)`
      # @option options [Integer] :batch_size (20_000) Number of rows to process in a single background migration run
      # @option options [Integer] :sub_batch_size (1000) Smaller batches size that the batches will be divided into
      # @option options [Integer] :batch_pause (0) Pause interval between each background migration job's execution (in seconds)
      # @option options [Integer] :sub_batch_pause_ms (100) Number of milliseconds to sleep between each sub_batch execution
      # @option options [Integer] :batch_max_attempts (5) Maximum number of batch run attempts
      #
      # @return [OnlineMigrations::BackgroundMigrations::Migration]
      #
      # @example
      #   enqueue_background_migration("BackfillProjectIssuesCount",
      #       batch_size: 10_000, batch_max_attempts: 10)
      #
      #   # Given the background migration exists:
      #
      #   class BackfillProjectIssuesCount < OnlineMigrations::BackgroundMigration
      #     def relation
      #       Project.all
      #     end
      #
      #     def process_batch(projects)
      #       projects.update_all(
      #         "issues_count = (SELECT COUNT(*) FROM issues WHERE issues.project_id = projects.id)"
      #       )
      #     end
      #
      #     # To be able to track progress, you need to define this method
      #     def count
      #       Project.maximum(:id)
      #     end
      #   end
      #
      # @note For convenience, the enqueued background migration is run inline
      #     in development and test environments
      #
      def enqueue_background_migration(migration_name, *arguments, **options)
        options.assert_valid_keys(:batch_column_name, :min_value, :max_value, :batch_size, :sub_batch_size,
            :batch_pause, :sub_batch_pause_ms, :batch_max_attempts)

        migration = Migration.create!(
          migration_name: migration_name,
          arguments: arguments,
          **options
        )

        # For convenience in dev/test environments
        if Utils.developer_env?
          runner = MigrationRunner.new(migration)
          runner.run_all_migration_jobs
        end

        migration
      end
    end
  end
end
