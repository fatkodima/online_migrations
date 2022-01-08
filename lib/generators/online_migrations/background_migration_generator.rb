# frozen_string_literal: true

require "rails/generators"

module OnlineMigrations
  # @private
  class BackgroundMigrationGenerator < Rails::Generators::NamedBase
    source_root File.expand_path("templates", __dir__)
    desc "This generator creates a background migration file."

    def create_background_migration_file
      template_file = File.join(
        "lib/#{migrations_module_file_path}",
        class_path,
        "#{file_name}.rb"
      )
      template("background_migration.rb", template_file)
    end

    private
      def migrations_module_file_path
        migrations_module.underscore
      end

      def migrations_module
        OnlineMigrations.config.background_migrations.migrations_module
      end
  end
end
