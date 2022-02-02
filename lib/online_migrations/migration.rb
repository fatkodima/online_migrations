# frozen_string_literal: true

module OnlineMigrations
  module Migration
    # @private
    def migrate(direction)
      VerboseSqlLogs.enable if verbose_sql_logs?

      OnlineMigrations.current_migration = self
      command_checker.direction = direction

      super
    ensure
      VerboseSqlLogs.disable if verbose_sql_logs?
    end

    # @private
    def method_missing(method, *args, &block)
      if is_a?(ActiveRecord::Schema)
        super
      elsif command_checker.check(method, *args, &block)
        if !in_transaction?
          if method == :with_lock_retries
            connection.with_lock_retries(*args, &block)
          else
            connection.with_lock_retries { super }
          end
        else
          super
        end
      end
    end
    ruby2_keywords(:method_missing) if respond_to?(:ruby2_keywords, true)

    # Mark a command in the migration as safe, despite using a method that might otherwise be dangerous.
    #
    # @example
    #   safety_assured { remove_column(:users, :some_column) }
    #
    def safety_assured(&block)
      command_checker.safety_assured(&block)
    end

    # Stop running migrations.
    #
    # It is intended for use in custom checks.
    #
    # @example
    #   OnlineMigrations.config.add_check do |method, args|
    #     if method == :add_column && args[0].to_s == "users"
    #       stop!("No more columns on the users table")
    #     end
    #   end
    #
    def stop!(message, header: "Custom check")
      raise OnlineMigrations::UnsafeMigration, "⚠️  [online_migrations] #{header} ⚠️\n\n#{message}\n\n"
    end

    private
      def verbose_sql_logs?
        if (verbose = ENV["ONLINE_MIGRATIONS_VERBOSE_SQL_LOGS"])
          Utils.to_bool(verbose)
        else
          OnlineMigrations.config.verbose_sql_logs
        end
      end

      def command_checker
        @command_checker ||= CommandChecker.new(self)
      end

      def in_transaction?
        connection.open_transactions > 0
      end
  end
end
