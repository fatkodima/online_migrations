# frozen_string_literal: true

module OnlineMigrations
  module Migration
    # @private
    def migrate(direction)
      OnlineMigrations.current_migration = self
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

    def stop!(message, header: "Dangerous operation detected")
      raise OnlineMigrations::UnsafeMigration, "⚠️  [online_migrations] #{header} ⚠️\n\n#{message}\n\n"
    end

    private
      def command_checker
        @command_checker ||= CommandChecker.new(self)
      end
  end
end
