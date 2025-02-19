# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record/migration"

module OnlineMigrations
  # @private
  class UpgradeGenerator < Rails::Generators::Base
    include ActiveRecord::Generators::Migration

    source_root File.expand_path("templates", __dir__)

    def copy_templates
      migrations_to_apply.each do |migration|
        migration_template("#{migration}.rb", File.join(db_migrate_path, "#{migration}.rb"))
      end
    end

    private
      def migrations_to_apply
        connection = BackgroundDataMigrations::Migration.connection
        data_table = "background_migrations"
        schema_table = "background_schema_migrations"
        columns = connection.columns(data_table).map(&:name)

        migrations = []
        if connection.table_exists?(data_table) && !columns.include?("shard")
          migrations << "add_sharding_to_online_migrations"
        end

        if !connection.table_exists?(schema_table)
          migrations << "create_background_schema_migrations"
        end

        indexes = connection.indexes(schema_table)
        unique_index = indexes.find { |i| i.unique && i.columns.sort == ["connection_class_name", "migration_name", "shard"] }
        if !unique_index
          migrations << "background_schema_migrations_change_unique_index"
        end

        if connection.table_exists?(data_table) && !connection.column_exists?(data_table, :started_at)
          migrations << "add_timestamps_to_background_migrations"
        end

        if connection.table_exists?(data_table)
          migrations << "change_background_data_migrations"
        end

        migrations
      end

      def migration_parent
        "ActiveRecord::Migration[#{Utils.ar_version}]"
      end
  end
end
