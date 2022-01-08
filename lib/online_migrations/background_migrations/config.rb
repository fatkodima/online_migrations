# frozen_string_literal: true

module OnlineMigrations
  module BackgroundMigrations
    # Class representing configuration options for background migrations.
    class Config
      # The module to namespace background migrations in
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

      # The number of seconds that must pass before the running job is considered stuck
      #
      # @return [Integer] defaults to 1 hour
      #
      attr_accessor :stuck_jobs_timeout

      def initialize
        @migrations_module = "OnlineMigrations::BackgroundMigrations"
        @batch_size = 20_000
        @sub_batch_size = 1000
        @batch_pause = 0.seconds
        @sub_batch_pause_ms = 100
        @batch_max_attempts = 5
        @stuck_jobs_timeout = 1.hour
      end
    end
  end
end