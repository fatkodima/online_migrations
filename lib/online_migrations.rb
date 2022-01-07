# frozen_string_literal: true

require "active_record"

require "online_migrations/utils"
require "online_migrations/error_messages"
require "online_migrations/config"
require "online_migrations/batch_iterator"
require "online_migrations/migration"
require "online_migrations/database_tasks"
require "online_migrations/foreign_keys_collector"
require "online_migrations/indexes_collector"
require "online_migrations/command_checker"
require "online_migrations/schema_cache"
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

      ActiveRecord::Tasks::DatabaseTasks.singleton_class.prepend(OnlineMigrations::DatabaseTasks)
      ActiveRecord::ConnectionAdapters::SchemaCache.prepend(OnlineMigrations::SchemaCache)
    end
  end
end

ActiveSupport.on_load(:active_record) do
  OnlineMigrations.load
end
