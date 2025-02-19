# frozen_string_literal: true

require "active_record"

require "online_migrations/version"
require "online_migrations/utils"
require "online_migrations/background_schema_migrations/migration_helpers"
require "online_migrations/change_column_type_helpers"
require "online_migrations/background_data_migrations/migration_helpers"
require "online_migrations/active_record_batch_enumerator"
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
  autoload :CommandChecker
  autoload :DataMigration
  autoload :ShardAware

  autoload_at "online_migrations/lock_retrier" do
    autoload :LockRetrier
    autoload :ConstantLockRetrier
    autoload :ExponentialLockRetrier
    autoload :NullLockRetrier
  end

  autoload :CopyTrigger

  module BackgroundDataMigrations
    extend ActiveSupport::Autoload

    autoload :Config
    autoload :MigrationStatusValidator
    autoload :BackfillColumn
    autoload :CopyColumn
    autoload :DeleteAssociatedRecords
    autoload :DeleteOrphanedRecords
    autoload :PerformActionOnRelation
    autoload :ResetCounters
    autoload :Migration
    autoload :MigrationJob
    autoload :Scheduler
    autoload :Ticker
  end

  module BackgroundSchemaMigrations
    extend ActiveSupport::Autoload

    autoload :Config
    autoload :Migration
    autoload :MigrationStatusValidator
    autoload :MigrationRunner
    autoload :Scheduler
  end

  # Make aliases for less typing.
  DataMigrations = BackgroundDataMigrations
  SchemaMigrations = BackgroundSchemaMigrations

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
    #
    # @option options [String, Symbol, nil] :shard The name of the shard to run
    #   background data migrations on. By default runs on all shards.
    #
    def run_background_data_migrations(**options)
      BackgroundDataMigrations::Scheduler.run(**options)
    end
    alias run_background_migrations run_background_data_migrations

    # Run background schema migrations
    #
    # @option options [String, Symbol, nil] :shard The name of the shard to run
    #   background schema migrations on. By default runs on all shards.
    #
    def run_background_schema_migrations(**options)
      BackgroundSchemaMigrations::Scheduler.run(**options)
    end

    def deprecator
      @deprecator ||= ActiveSupport::Deprecation.new(nil, "online_migrations")
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
      else
        ActiveRecord::ConnectionAdapters::SchemaCache.prepend(OnlineMigrations::SchemaCache)
      end

      if !ActiveRecord::Batches::BatchEnumerator.method_defined?(:use_ranges)
        ActiveRecord::Batches::BatchEnumerator.include(OnlineMigrations::ActiveRecordBatchEnumerator)
      end
    end
  end
end

ActiveSupport.on_load(:active_record) do
  OnlineMigrations.load
end
