# frozen_string_literal: true

module OnlineMigrations
  # Class representing configuration options for the gem.
  class Config
    include ErrorMessages

    # The database version against which the checks will be performed
    #
    # If your development database version is different from production, you can specify
    # the production version so the right checks run in development.
    #
    # @example Set specific target version
    #   MigrationHelpers.config.target_version = 10
    #
    attr_accessor :target_version

    # Whether to perform checks when migrating down
    #
    # Disabled by default
    # @return [Boolean]
    #
    attr_accessor :check_down

    attr_accessor :error_messages

    def initialize
      @error_messages = ERROR_MESSAGES
      @check_down = false
    end
  end
end
