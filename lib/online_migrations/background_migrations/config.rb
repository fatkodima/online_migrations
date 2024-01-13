# frozen_string_literal: true

module OnlineMigrations
  module BackgroundMigrations
    # Class representing configuration options for background migrations.
    class Config
      # The path where generated background migrations will be placed
      # @return [String] defaults to "lib"
      attr_accessor :migrations_path

      # The module in which background migrations will be placed
      # @return [String] defaults to "OnlineMigrations::BackgroundMigrations"
      attr_accessor :migrations_module

      # The number of rows to process in a single background migration run
      # @return [Integer] defaults to 20_000
      #
      attr_accessor :batch_size

      # The smaller batches size that the batches will be divided into
      # @return [Integer] defaults to 1000
      #
      attr_accessor :sub_batch_size

      # The pause interval between each background migration job's execution (in seconds)
      # @return [Integer] defaults to 0
      #
      attr_accessor :batch_pause

      # The number of milliseconds to sleep between each sub_batch execution
      # @return [Integer] defaults to 100 milliseconds
      #
      attr_accessor :sub_batch_pause_ms

      # Maximum number of batch run attempts
      #
      # When attempts are exhausted, the individual batch is marked as failed.
      # @return [Integer] defaults to 5
      #
      attr_accessor :batch_max_attempts

      def throttler
        OnlineMigrations.deprecator.warn(<<~MSG)
          `config.background_migrations.throttler` is deprecated and will be removed.
          Use `config.throttler` instead.
        MSG
        OnlineMigrations.config.throttler
      end

      # The number of seconds that must pass before the running job is considered stuck
      #
      # @return [Integer] defaults to 1 hour
      #
      attr_accessor :stuck_jobs_timeout

      def backtrace_cleaner
        OnlineMigrations.deprecator.warn(<<~MSG)
          `config.background_migrations.backtrace_cleaner` is deprecated and will be removed.
          Use `config.backtrace_cleaner` instead.
        MSG
        OnlineMigrations.config.backtrace_cleaner
      end

      def backtrace_cleaner=(value)
        OnlineMigrations.deprecator.warn(<<~MSG)
          `config.background_migrations.backtrace_cleaner=` is deprecated and will be removed.
          Use `config.backtrace_cleaner=` instead.
        MSG
        OnlineMigrations.config.backtrace_cleaner = value
      end

      # The callback to perform when an error occurs in the migration job.
      #
      # @example
      #   OnlineMigrations.config.background_migrations.error_handler = ->(error, errored_job) do
      #     Bugsnag.notify(error) do |notification|
      #       notification.add_metadata(:background_migration, { name: errored_job.migration_name })
      #     end
      #   end
      #
      # @return [Proc] the callback to perform when an error occurs in the migration job
      #
      attr_accessor :error_handler

      def initialize
        @migrations_path = "lib"
        @migrations_module = "OnlineMigrations::BackgroundMigrations"
        @batch_size = 20_000
        @sub_batch_size = 1000
        @batch_pause = 0.seconds
        @sub_batch_pause_ms = 100
        @batch_max_attempts = 5
        @stuck_jobs_timeout = 1.hour
        @error_handler = ->(error, errored_job) {}
      end

      def throttler=(value)
        OnlineMigrations.deprecator.warn(<<~MSG)
          `config.background_migrations.throttler=` is deprecated and will be removed.
          Use `config.throttler=` instead.
        MSG
        OnlineMigrations.config.throttler = value
      end
    end
  end
end
