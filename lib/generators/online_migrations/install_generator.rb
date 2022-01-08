# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record/migration"

module OnlineMigrations
  # @private
  class InstallGenerator < Rails::Generators::Base
    include ActiveRecord::Generators::Migration

    source_root File.expand_path("templates", __dir__)

    def create_migration_file
      migration_template("migration.rb", File.join(migrations_dir, "install_online_migrations.rb"))
    end

    private
      def migration_parent
        Utils.migration_parent_string
      end

      def migrations_dir
        Utils.ar_version >= 5.1 ? db_migrate_path : "db/migrate"
      end
  end
end
