# frozen_string_literal: true

module OnlineMigrations
  # Class representing configuration options for the gem.
  class Config
    include ErrorMessages

    # The migration version starting from which checks are performed
    # @return [Integer]
    #
    attr_accessor :start_after

    # The database version against which the checks will be performed
    #
    # If your development database version is different from production, you can specify
    # the production version so the right checks run in development.
    #
    # @example Set specific target version
    #   OnlineMigrations.config.target_version = 10
    #
    attr_accessor :target_version

    # Whether to perform checks when migrating down
    #
    # Disabled by default
    # @return [Boolean]
    #
    attr_accessor :check_down

    # Error messages
    #
    # @return [Hash] Keys are error names, values are error messages
    # @example To change a message
    #   OnlineMigrations.config.error_messages[:remove_column] = "Your custom instructions"
    #
    attr_accessor :error_messages

    # Maximum allowed lock timeout value (in seconds)
    #
    # If set lock timeout is greater than this value, the migration will fail.
    # The default value is 10 seconds.
    #
    # @return [Numeric]
    #
    attr_accessor :lock_timeout_limit

    # Tables that are in the process of being renamed
    #
    # @return [Hash] Keys are old table names, values - new table names
    # @example To add a table
    #   OnlineMigrations.config.table_renames["users"] = "clients"
    #
    attr_accessor :table_renames

    # Columns that are in the process of being renamed
    #
    # @return [Hash] Keys are table names, values - hashes with old column names as keys
    #   and new column names as values
    # @example To add a column
    #   OnlineMigrations.config.column_renames["users] = { "name" => "first_name" }
    #
    attr_accessor :column_renames

    def initialize
      @table_renames = {}
      @column_renames = {}
      @error_messages = ERROR_MESSAGES
      @lock_timeout_limit = 10.seconds
      @start_after = 0
      @check_down = false
    end
  end
end
