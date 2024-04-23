# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record/migration"

module OnlineMigrations
  # @private
  class BackgroundMigrationGenerator < Rails::Generators::NamedBase
    include ActiveRecord::Generators::Migration

    source_root File.expand_path("templates", __dir__)
    desc "This generator creates a background migration related files."

    def create_background_data_migration_file
      migrations_module_file_path = migrations_module.underscore

      template_file = File.join(
        config.migrations_path,
        migrations_module_file_path,
        class_path,
        "#{file_name}.rb"
      )
      template("background_data_migration.rb", template_file)
    end

    def create_migration_file
      migration_template("migration.rb", File.join(db_migrate_path, "enqueue_#{file_name}.rb"))
    end

    private
      def migrations_module
        config.migrations_module
      end

      def config
        OnlineMigrations.config.background_migrations
      end

      def migration_parent
        "ActiveRecord::Migration[#{Utils.ar_version}]"
      end
  end
end
