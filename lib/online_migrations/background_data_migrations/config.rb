# frozen_string_literal: true

module OnlineMigrations
  module BackgroundDataMigrations
    # Class representing configuration options for data migrations.
    class Config
      # The path where generated data migrations will be placed.
      # @return [String] defaults to "lib"
      attr_accessor :migrations_path

      # The module in which data migrations will be placed.
      # @return [String] defaults to "OnlineMigrations::DataMigrations"
      attr_accessor :migrations_module

      # Maximum number of run attempts.
      #
      # When attempts are exhausted, the data migration is marked as failed.
      # @return [Integer] defaults to 5
      attr_accessor :max_attempts

      # The number of seconds that must pass before the cancelling or pausing data migration is considered stuck.
      #
      # @return [Integer] defaults to 5 minutes
      #
      attr_accessor :stuck_timeout

      # The pause interval between each data migration's `process` method execution (in seconds).
      # @return [Integer] defaults to 0
      #
      attr_accessor :iteration_pause

      # The callback to perform when an error occurs during the data migration.
      #
      # @example
      #   OnlineMigrations.config.background_migrations.error_handler = ->(error, errored_migration) do
      #     Bugsnag.notify(error) do |notification|
      #       notification.add_metadata(:background_migration, { name: errored_migration.migration_name })
      #     end
      #   end
      #
      # @return [Proc]
      #
      attr_accessor :error_handler

      # The name of the sidekiq job to be used to perform data migrations.
      #
      # @return [String] defaults to "OnlineMigrations::BackgroundDataMigrations::MigrationJob"
      #
      attr_accessor :job

      def initialize
        @migrations_path = "lib"
        @migrations_module = "OnlineMigrations::DataMigrations"
        @max_attempts = 5
        @stuck_timeout = 5.minutes
        @iteration_pause = 0.seconds
        @error_handler = ->(error, errored_migration) {}
        @job = "OnlineMigrations::BackgroundDataMigrations::MigrationJob"
      end
    end
  end
end
