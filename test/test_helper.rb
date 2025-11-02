# frozen_string_literal: true

require "logger"
require "online_migrations"

require "minitest/autorun"

# Required to be able to run single tests via command line.
require "active_support/core_ext/string/strip"

require "sidekiq/testing"

# Needed for `developer_env?`
module Rails
  def self.env
    ActiveSupport::StringInquirer.new("test")
  end
end

database_yml = File.expand_path("support/database.yml", __dir__)

ActiveRecord::Base.configurations =
  begin
    YAML.load_file(database_yml, aliases: true)
  rescue ArgumentError
    YAML.load_file(database_yml)
  end

ActiveRecord::Base.establish_connection(:test)

if OnlineMigrations::Utils.ar_version >= 7.2
  # https://github.com/rails/rails/pull/50284
  ActiveRecord::Base.automatically_invert_plural_associations = true
end

if ENV["VERBOSE"]
  ActiveRecord::Base.logger = ActiveSupport::Logger.new($stdout)
else
  ActiveRecord::Base.logger = ActiveSupport::Logger.new("debug.log", 1, 100 * 1024 * 1024) # 100 mb
  ActiveRecord::Migration.verbose = false
end

# Disallow ActiveSupport deprecations sprouting from this gem
ActiveRecord.deprecator.disallowed_warnings = :all

# Is a boolean value and controls whether or not partial writes are used when creating new records
# (i.e. whether inserts only set attributes that are different from the default). The default value is true.
# This should be enabled when renaming columns, because the SchemaCache will return both (old and new)
# columns and otherwise inserts will try to set both columns which will lead to "multiple assignments to same column"
# PG error.
#
# Another option is to suggest users to set/unset `ignored_columns` when needed, but since
# partial writes are enabled by default, no action from users will be needed.
ActiveRecord::Base.partial_inserts = true

def prepare_database
  connection = ActiveRecord::Base.connection
  connection.tables.each do |table_name|
    connection.drop_table(table_name, force: :cascade)
  end

  if OnlineMigrations::Utils.ar_version >= 7.2
    ActiveRecord::SchemaMigration.new(connection.pool).create_table
  else
    ActiveRecord::SchemaMigration.new(connection).create_table
  end
end

prepare_database

TestMigration = ActiveRecord::Migration::Current
TestMigration.version = 20200101000001

OnlineMigrations.configure do |config|
  config.background_data_migrations.migrations_module = "BackgroundDataMigrations"
end

require_relative "support/schema"
require_relative "support/minitest_helpers"
require_relative "support/models"
require_relative "background_data_migrations/data_migrations"

# Load database schema into shards.
[:shard_one, :shard_two, :shard_no_database_tasks].each do |shard|
  ShardRecord.connected_to(shard: shard, role: :writing) do
    connection = ShardRecord.connection
    connection.create_table(:dogs, force: true) do |t|
      t.string :name
      t.boolean :nice, default: nil
    end
  end
end
