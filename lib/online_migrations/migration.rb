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

    def stop!(message, header: "Dangerous operation detected")
      raise OnlineMigrations::UnsafeMigration, "⚠️  [online_migrations] #{header} ⚠️\n\n#{message}\n\n"
    end

    private
      def command_checker
        @command_checker ||= CommandChecker.new(self)
      end
  end
end
