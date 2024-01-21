# frozen_string_literal: true

require "rails/generators"

module OnlineMigrations
  # @private
  class BackgroundMigrationGenerator < Rails::Generators::NamedBase
    source_root File.expand_path("templates", __dir__)
    desc "This generator creates a background migration file."

    def create_background_migration_file
      migrations_module_file_path = migrations_module.underscore

      template_file = File.join(
        config.migrations_path,
        migrations_module_file_path,
        class_path,
        "#{file_name}.rb"
      )
      template("background_migration.rb", template_file)
    end

    private
      def migrations_module
        config.migrations_module
      end

      def config
        OnlineMigrations.config.background_migrations
      end
  end
end
