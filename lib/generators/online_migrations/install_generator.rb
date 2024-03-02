# frozen_string_literal: true

require "rails/generators"
require "rails/generators/active_record/migration"

module OnlineMigrations
  # @private
  class InstallGenerator < Rails::Generators::Base
    include ActiveRecord::Generators::Migration

    source_root File.expand_path("templates", __dir__)

    def copy_initializer_file
      template("initializer.rb", "config/initializers/online_migrations.rb")
    end

    def create_migration_file
      migration_template("install_migration.rb", File.join(db_migrate_path, "install_online_migrations.rb"))
    end

    private
      def migration_parent
        "ActiveRecord::Migration[#{Utils.ar_version}]"
      end

      def start_after
        self.class.current_migration_number(db_migrate_path)
      end
  end
end
