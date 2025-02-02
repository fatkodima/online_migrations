# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record/migration"

module OnlineMigrations
  # @private
  class UpgradeGenerator < Rails::Generators::Base
    include ActiveRecord::Generators::Migration

    source_root File.expand_path("templates", __dir__)

    def copy_templates
      migrations_to_be_applied.each do |migration|
        migration_template("#{migration}.rb", File.join(db_migrate_path, "#{migration}.rb"))
      end
    end

    private
      def migrations_to_be_applied
        connection = BackgroundMigrations::Migration.connection
        columns = connection.columns(BackgroundMigrations::Migration.table_name).map(&:name)

        migrations = []
        migrations << "add_sharding_to_online_migrations" if !columns.include?("shard")

        if !connection.table_exists?(BackgroundSchemaMigrations::Migration.table_name)
          migrations << "create_background_schema_migrations"
        end

        indexes = connection.indexes(BackgroundSchemaMigrations::Migration.table_name)
        unique_index = indexes.find { |i| i.unique && i.columns.sort == ["connection_class_name", "migration_name", "shard"] }
        if !unique_index
          migrations << "background_schema_migrations_change_unique_index"
        end

        if !connection.column_exists?(BackgroundMigrations::Migration.table_name, :started_at)
          migrations << "add_timestamps_to_background_migrations"
        end

        migrations
      end

      def migration_parent
        "ActiveRecord::Migration[#{Utils.ar_version}]"
      end
  end
end
