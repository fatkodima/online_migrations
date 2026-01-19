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

        migrations = []
        if connection.table_exists?(:background_migrations) && !connection.column_exists?(:background_migrations, :shard)
          migrations << "add_sharding_to_online_migrations"
        end

        if !connection.table_exists?(:background_schema_migrations)
          migrations << "create_background_schema_migrations"
        end

        indexes = connection.indexes(:background_schema_migrations)
        unique_index = indexes.find { |i| i.unique && i.columns.sort == ["connection_class_name", "migration_name", "shard", "table_name"] }
        if !unique_index
          migrations << "background_schema_migrations_change_unique_index"
        end

        if connection.table_exists?(:background_migrations) && !connection.column_exists?(:background_migrations, :started_at)
          migrations << "add_timestamps_to_background_migrations"
        end

        if connection.table_exists?(:background_migrations)
          migrations << "change_background_data_migrations"
        end

        if !connection.column_exists?(:background_data_migrations, :iteration_pause)
          migrations << "background_data_migrations_add_iteration_pause"
        end

        iteration_pause_column = connection.columns(:background_data_migrations).find { |c| c.name == "iteration_pause" }
        if iteration_pause_column && iteration_pause_column.default
          migrations << "background_data_migrations_remove_iteration_pause_default"
        end

        status_column = connection.columns(:background_data_migrations).find { |c| c.name == "status" }
        if status_column.default == "enqueued"
          migrations << "background_migrations_change_status_default"
        end

        migrations
      end

      def migration_parent
        "ActiveRecord::Migration[#{Utils.ar_version}]"
      end
  end
end
