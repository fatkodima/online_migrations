# frozen_string_literal: true

module OnlineMigrations
  # Class representing configuration options for the gem.
  class Config
    include ErrorMessages

    # Set the migration version starting after which checks are performed
    # @example
    #   OnlineMigrations.config.start_after = 20220101000000
    #
    # @example Multiple databases
    #   OnlineMigrations.config.start_after = { primary: 20211112000000, animals: 20220101000000 }
    #
    # @note Use the version from your latest migration.
    #
    def start_after=(value)
      if value.is_a?(Hash)
        @start_after = value.stringify_keys
      else
        @start_after = value
      end
    end

    # The migration version starting after which checks are performed
    # @return [Integer]
    #
    def start_after
      if @start_after.is_a?(Hash)
        @start_after.fetch(db_config_name) do
          raise "OnlineMigrations.config.start_after is not configured for :#{db_config_name}"
        end
      else
        @start_after
      end
    end

    # Statement timeout used for migrations (in seconds)
    #
    # @return [Numeric]
    #
    attr_accessor :statement_timeout

    # Set the database version against which the checks will be performed
    #
    # If your development database version is different from production, you can specify
    # the production version so the right checks run in development.
    #
    # @example
    #   OnlineMigrations.config.target_version = 10
    #
    # @example Multiple databases
    #   OnlineMigrations.config.target_version = { primary: 10, animals: 14.1 }
    #
    def target_version=(value)
      if value.is_a?(Hash)
        @target_version = value.stringify_keys
      else
        @target_version = value
      end
    end

    # The database version against which the checks will be performed
    # @return [Numeric, String, nil]
    #
    def target_version
      if @target_version.is_a?(Hash)
        @target_version.fetch(db_config_name) do
          raise "OnlineMigrations.config.target_version is not configured for :#{db_config_name}"
        end
      else
        @target_version
      end
    end

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

    # Whether to automatically run ANALYZE on the table after the index was added
    # @return [Boolean]
    #
    attr_accessor :auto_analyze

    # Whether to alphabetize schema
    # @return [Boolean]
    #
    attr_accessor :alphabetize_schema

    # Maximum allowed lock timeout value (in seconds)
    #
    # If set lock timeout is greater than this value, the migration will fail.
    # The default value is 10 seconds.
    #
    # @return [Numeric]
    #
    attr_accessor :lock_timeout_limit

    # List of tables with permanently small number of records
    #
    # These are usually tables like "settings", "prices", "plans" etc.
    # It is considered safe to perform most of the dangerous operations on them,
    #   like adding indexes, columns etc.
    #
    # @return [Array<String, Symbol>]
    #
    attr_reader :small_tables

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

    # Lock retrier in use (see LockRetrier)
    #
    # No retries are performed by default.
    # @return [OnlineMigrations::LockRetrier]
    #
    attr_reader :lock_retrier

    # Returns a list of custom checks
    #
    # Use `add_check` to add custom checks
    #
    # @return [Array<Array<Hash>, Proc>]
    #
    attr_reader :checks

    # Returns a list of enabled checks
    #
    # All checks are enabled by default. To disable/enable a check use `disable_check`/`enable_check`.
    # For the list of available checks look at the `error_messages.rb` file.
    #
    # @return [Array]
    #
    attr_reader :enabled_checks

    # Whether to log every SQL query happening in a migration
    #
    # This is useful to demystify online_migrations inner workings, and to better investigate
    # migration failure in production. This is also useful in development to get
    # a better grasp of what is going on for high-level statements like add_column_with_default.
    #
    # This feature is enabled by default in a staging and production Rails environments.
    # @return [Boolean]
    #
    # @note: It can be overridden by `ONLINE_MIGRATIONS_VERBOSE_SQL_LOGS` environment variable.
    #
    attr_accessor :verbose_sql_logs

    # Configuration object to configure background migrations
    #
    # @return [BackgroundMigrationsConfig]
    # @see BackgroundMigrationsConfig
    #
    attr_reader :background_migrations

    def initialize
      @table_renames = {}
      @column_renames = {}
      @error_messages = ERROR_MESSAGES
      @lock_timeout_limit = 10.seconds

      @lock_retrier = ExponentialLockRetrier.new(
        attempts: 30,
        base_delay: 0.01.seconds,
        max_delay: 1.minute,
        lock_timeout: 0.2.seconds
      )

      @background_migrations = BackgroundMigrations::Config.new

      @checks = []
      @start_after = 0
      @target_version = nil
      @small_tables = []
      @check_down = false
      @auto_analyze = false
      @alphabetize_schema = false
      @enabled_checks = @error_messages.keys.index_with({})
      @verbose_sql_logs = defined?(Rails.env) && (Rails.env.production? || Rails.env.staging?)
    end

    def lock_retrier=(value)
      @lock_retrier = value || NullLockRetrier.new
    end

    def small_tables=(table_names)
      @small_tables = table_names.map(&:to_s)
    end

    # Enables specific check
    #
    # For the list of available checks look at the `error_messages.rb` file.
    #
    # @param name [Symbol] check name
    # @param start_after [Integer] migration version from which this check will be performed
    # @return [void]
    #
    def enable_check(name, start_after: nil)
      enabled_checks[name] = { start_after: start_after }
    end

    # Disables specific check
    #
    # For the list of available checks look at the `error_messages.rb` file.
    #
    # @param name [Symbol] check name
    # @return [void]
    #
    def disable_check(name)
      enabled_checks.delete(name)
    end

    # Test whether specific check is enabled
    #
    # For the list of available checks look at the `error_messages.rb` file.
    #
    # @param name [Symbol] check name
    # @param version [Integer] migration version
    # @return [void]
    #
    def check_enabled?(name, version: nil)
      if enabled_checks[name]
        start_after = enabled_checks[name][:start_after] || OnlineMigrations.config.start_after
        !version || version > start_after
      else
        false
      end
    end

    # Adds custom check
    #
    # @param start_after [Integer] migration version from which this check will be performed
    #
    # @yield [method, args] a block to be called with custom check
    # @yieldparam method [Symbol] method name
    # @yieldparam args [Array] method arguments
    #
    # @return [void]
    #
    # Use `stop!` method to stop the migration
    #
    # @example
    #   OnlineMigrations.config.add_check do |method, args|
    #     if method == :add_column && args[0].to_s == "users"
    #       stop!("No more columns on the users table")
    #     end
    #   end
    #
    def add_check(start_after: nil, &block)
      @checks << [{ start_after: start_after }, block]
    end

    private
      def db_config_name
        connection = OnlineMigrations.current_migration.connection
        connection.pool.db_config.name
      end
  end
end
