# frozen_string_literal: true

require "active_record"

require "online_migrations/version"
require "online_migrations/utils"
require "online_migrations/background_schema_migrations/migration_helpers"
require "online_migrations/change_column_type_helpers"
require "online_migrations/background_migrations/migration_helpers"
require "online_migrations/schema_statements"
require "online_migrations/schema_cache"
require "online_migrations/migration"
require "online_migrations/migrator"
require "online_migrations/schema_dumper"
require "online_migrations/database_tasks"
require "online_migrations/command_recorder"
require "online_migrations/error_messages"
require "online_migrations/config"

module OnlineMigrations
  class Error < StandardError; end
  class UnsafeMigration < Error; end

  extend ActiveSupport::Autoload

  autoload :ApplicationRecord
  autoload :BatchIterator
  autoload :VerboseSqlLogs
  autoload :ForeignKeysCollector
  autoload :IndexDefinition
  autoload :IndexesCollector
  autoload :CommandChecker
  autoload :BackgroundMigration

  autoload_at "online_migrations/lock_retrier" do
    autoload :LockRetrier
    autoload :ConstantLockRetrier
    autoload :ExponentialLockRetrier
    autoload :NullLockRetrier
  end

  autoload :CopyTrigger

  module BackgroundMigrations
    extend ActiveSupport::Autoload

    autoload :Config
    autoload :MigrationStatusValidator
    autoload :MigrationJobStatusValidator
    autoload :BackgroundMigrationClassValidator
    autoload :BackfillColumn
    autoload :CopyColumn
    autoload :DeleteAssociatedRecords
    autoload :DeleteOrphanedRecords
    autoload :PerformActionOnRelation
    autoload :ResetCounters
    autoload :MigrationJob
    autoload :Migration
    autoload :MigrationJobRunner
    autoload :MigrationRunner
    autoload :Scheduler
  end

  module BackgroundSchemaMigrations
    extend ActiveSupport::Autoload

    autoload :Config
    autoload :Migration
    autoload :MigrationStatusValidator
    autoload :MigrationRunner
    autoload :Scheduler
  end

  class << self
    # @private
    attr_accessor :current_migration

    def configure
      yield config
    end

    def config
      @config ||= Config.new
    end

    # Run background data migrations
    def run_background_migrations
      BackgroundMigrations::Scheduler.run
    end
    alias run_background_data_migrations run_background_migrations

    # Run background schema migrations
    def run_background_schema_migrations
      BackgroundSchemaMigrations::Scheduler.run
    end

    def deprecator
      @deprecator ||=
        if Utils.ar_version >= 7.1
          ActiveSupport::Deprecation.new(nil, "online_migrations")
        else
          ActiveSupport::Deprecation
        end
    end

    # @private
    def load
      require "active_record/connection_adapters/postgresql_adapter"
      ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.prepend(OnlineMigrations::SchemaStatements)

      ActiveRecord::Migration.prepend(OnlineMigrations::Migration)
      ActiveRecord::Migrator.prepend(OnlineMigrations::Migrator)
      ActiveRecord::SchemaDumper.prepend(OnlineMigrations::SchemaDumper)

      ActiveRecord::Tasks::DatabaseTasks.singleton_class.prepend(OnlineMigrations::DatabaseTasks)
      ActiveRecord::Migration::CommandRecorder.include(OnlineMigrations::CommandRecorder)

      if OnlineMigrations::Utils.ar_version >= 7.2
        ActiveRecord::ConnectionAdapters::SchemaCache.prepend(OnlineMigrations::SchemaCache72)
      elsif OnlineMigrations::Utils.ar_version >= 7.1
        ActiveRecord::ConnectionAdapters::SchemaCache.prepend(OnlineMigrations::SchemaCache71)
      else
        ActiveRecord::ConnectionAdapters::SchemaCache.prepend(OnlineMigrations::SchemaCache)
      end
    end
  end
end

ActiveSupport.on_load(:active_record) do
  OnlineMigrations.load
end
