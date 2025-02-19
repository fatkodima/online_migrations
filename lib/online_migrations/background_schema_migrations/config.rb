# frozen_string_literal: true

module OnlineMigrations
  module BackgroundSchemaMigrations
    # Class representing configuration options for background schema migrations.
    class Config
      # Maximum number of run attempts.
      #
      # When attempts are exhausted, the schema migration is marked as failed.
      # @return [Integer] defaults to 5
      #
      attr_accessor :max_attempts

      # Statement timeout value used when running background schema migration.
      #
      # @return [Integer] defaults to 1 hour
      #
      attr_accessor :statement_timeout

      # The callback to perform when an error occurs in the migration.
      #
      # @example
      #   OnlineMigrations.config.background_schema_migrations.error_handler = ->(error, errored_migration) do
      #     Bugsnag.notify(error) do |notification|
      #       notification.add_metadata(:background_schema_migration, { name: errored_migration.name })
      #     end
      #   end
      #
      # @return [Proc] the callback to perform when an error occurs in the migration
      #
      attr_accessor :error_handler

      def initialize
        @max_attempts = 5
        @statement_timeout = 1.hour
        @error_handler = ->(error, errored_migration) {}
      end
    end
  end
end
