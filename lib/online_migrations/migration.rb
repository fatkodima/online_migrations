# frozen_string_literal: true

module OnlineMigrations
  module Migration
    # @private
    def migrate(direction)
      OnlineMigrations.current_migration = self
      command_checker.direction = direction
      super
    end

    # @private
    def method_missing(method, *args, &block)
      if is_a?(ActiveRecord::Schema)
        super
      elsif command_checker.check(method, *args, &block)
        super
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
      def command_checker
        @command_checker ||= CommandChecker.new(self)
      end
  end
end
