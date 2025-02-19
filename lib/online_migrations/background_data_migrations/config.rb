# frozen_string_literal: true

module OnlineMigrations
  module BackgroundDataMigrations
    # Class representing configuration options for background migrations.
    class Config
      # The path where generated background migrations will be placed.
      # @return [String] defaults to "lib"
      attr_accessor :migrations_path

      # The module in which background migrations will be placed.
      # @return [String] defaults to "OnlineMigrations::DataMigrations"
      attr_accessor :migrations_module

      # Maximum number of batch run attempts.
      #
      # When attempts are exhausted, the individual batch is marked as failed.
      # @return [Integer] defaults to 5
      #
      attr_accessor :max_attempts

      # The number of seconds that must pass before the running migration is considered stuck.
      #
      # @return [Integer] defaults to 5 minutes
      #
      attr_accessor :stuck_timeout

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

      # The name of the job to be used to perform background data migrations.
      #
      # @return [String] defaults to "OnlineMigrations::BackgroundMigrations::MigrationJob"
      #
      attr_accessor :job

      def initialize
        @migrations_path = "lib"
        @migrations_module = "OnlineMigrations::DataMigrations"
        @max_attempts = 5
        @stuck_timeout = 5.minutes
        @error_handler = ->(error, errored_job) {}
        @job = "OnlineMigrations::BackgroundDataMigrations::MigrationJob"
      end
    end
  end
end
