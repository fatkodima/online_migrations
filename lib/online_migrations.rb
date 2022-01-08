# frozen_string_literal: true

require "active_record"

require "online_migrations/utils"
require "online_migrations/error_messages"
require "online_migrations/config"
require "online_migrations/batch_iterator"
require "online_migrations/migration"
require "online_migrations/migrator"
require "online_migrations/database_tasks"
require "online_migrations/foreign_key_definition"
require "online_migrations/foreign_keys_collector"
require "online_migrations/indexes_collector"
require "online_migrations/command_checker"
require "online_migrations/schema_cache"
require "online_migrations/background_migration"
require "online_migrations/background_migrations/config"
require "online_migrations/background_migrations/migration_status_validator"
require "online_migrations/background_migrations/migration_job_status_validator"
require "online_migrations/background_migrations/background_migration_class_validator"
require "online_migrations/background_migrations/backfill_column"
require "online_migrations/background_migrations/copy_column"
require "online_migrations/background_migrations/migration_job"
require "online_migrations/background_migrations/migration"
require "online_migrations/background_migrations/migration_job_runner"
require "online_migrations/background_migrations/migration_runner"
require "online_migrations/background_migrations/migration_helpers"
require "online_migrations/lock_retrier"
require "online_migrations/copy_trigger"
require "online_migrations/change_column_type_helpers"
require "online_migrations/schema_statements"
require "online_migrations/version"

module OnlineMigrations
  class Error < StandardError; end
  class UnsafeMigration < Error; end

  class << self
    # @private
    attr_accessor :current_migration

    def configure
      yield config
    end

    def config
      @config ||= Config.new
    end

    def load
      require "active_record/connection_adapters/postgresql_adapter"
      ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.prepend(OnlineMigrations::SchemaStatements)

      ActiveRecord::Migration.prepend(OnlineMigrations::Migration)
      ActiveRecord::Migrator.prepend(OnlineMigrations::Migrator)

      ActiveRecord::Tasks::DatabaseTasks.singleton_class.prepend(OnlineMigrations::DatabaseTasks)
      ActiveRecord::ConnectionAdapters::SchemaCache.prepend(OnlineMigrations::SchemaCache)

      if OnlineMigrations::Utils.ar_version <= 5.1
        ActiveRecord::ConnectionAdapters::ForeignKeyDefinition.prepend(OnlineMigrations::ForeignKeyDefinition)
      end
    end
  end
end

ActiveSupport.on_load(:active_record) do
  OnlineMigrations.load
end
