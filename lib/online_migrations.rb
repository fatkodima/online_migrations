# frozen_string_literal: true

require "active_record"
require "online_migrations/version"

module OnlineMigrations
  class Error < StandardError; end
  class UnsafeMigration < Error; end

  extend ActiveSupport::Autoload

  autoload :Utils
  autoload :ErrorMessages
  autoload :Config
  autoload :BatchIterator
  autoload :VerboseSqlLogs
  autoload :Migration
  autoload :Migrator
  autoload :SchemaDumper
  autoload :DatabaseTasks
  autoload :ForeignKeysCollector
  autoload :IndexDefinition
  autoload :IndexesCollector
  autoload :CommandChecker
  autoload :BackgroundMigration

  autoload_at "online_migrations/schema_cache" do
    autoload :SchemaCache
    autoload :SchemaCache7
  end

  autoload_at "online_migrations/lock_retrier" do
    autoload :LockRetrier
    autoload :ConstantLockRetrier
    autoload :ExponentialLockRetrier
    autoload :NullLockRetrier
  end

  autoload :CommandRecorder
  autoload :CopyTrigger
  autoload :ChangeColumnTypeHelpers
  autoload :SchemaStatements

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
    autoload :ApplicationRecord
    autoload :MigrationJob
    autoload :Migration
    autoload :MigrationJobRunner
    autoload :MigrationRunner
    autoload :MigrationHelpers
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

    # Run background migrations
    def run_background_migrations
      BackgroundMigrations::Scheduler.run
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

      if OnlineMigrations::Utils.ar_version >= 7.1
        ActiveRecord::ConnectionAdapters::SchemaCache.prepend(OnlineMigrations::SchemaCache7)
      else
        ActiveRecord::ConnectionAdapters::SchemaCache.prepend(OnlineMigrations::SchemaCache)
      end
    end
  end
end

ActiveSupport.on_load(:active_record) do
  OnlineMigrations.load
end
