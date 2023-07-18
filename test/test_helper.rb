# frozen_string_literal: true

require "online_migrations"

require "minitest/autorun"

# Required to be able to run single tests via command line.
require "active_support/core_ext/string/strip"

# Needed for `developer_env?`
module Rails
  def self.env
    ActiveSupport::StringInquirer.new("test")
  end
end

database_yml = File.expand_path("support/database.yml", __dir__)
ActiveRecord::Base.configurations = YAML.load_file(database_yml)
ActiveRecord::Base.establish_connection(:postgresql)

if ENV["VERBOSE"]
  ActiveRecord::Base.logger = ActiveSupport::Logger.new($stdout)
else
  ActiveRecord::Base.logger = ActiveSupport::Logger.new("debug.log", 1, 100 * 1024 * 1024) # 100 mb
  ActiveRecord::Migration.verbose = false
end

# disallowed_warnings was added in Active Record 6.1
# Disallow ActiveSupport deprecations sprouting from this gem
if OnlineMigrations::Utils.ar_version >= 7.1
  ActiveSupport::Deprecation._instance.disallowed_warnings = :all
elsif OnlineMigrations::Utils.ar_version >= 6.1
  ActiveSupport::Deprecation.disallowed_warnings = :all
end

# Is a boolean value and controls whether or not partial writes are used when creating new records
# (i.e. whether inserts only set attributes that are different from the default). The default value is true.
# This should be enabled when renaming columns, because the SchemaCache will return both (old and new)
# columns and otherwise inserts will try to set both columns which will lead to "multiple assignments to same column"
# PG error.
#
# Another option is to suggest users to set/unset `ignored_columns` when needed, but since
# partial writes are enabled by default, no action from users will be needed.
ActiveRecord::Base.public_send("#{OnlineMigrations::Utils.ar_partial_writes_setting}=", true)

# Was added in https://github.com/rails/rails/pull/41718.
if OnlineMigrations::Utils.ar_version >= 7
  ActiveRecord::Base.enumerate_columns_in_select_statements = false # default in 7.0
end

def prepare_database
  connection = ActiveRecord::Base.connection
  connection.tables.each do |table_name|
    connection.drop_table(table_name, force: :cascade)
  end

  if OnlineMigrations::Utils.ar_version >= 7.1
    ActiveRecord::SchemaMigration.new(connection).create_table
  else
    ActiveRecord::SchemaMigration.create_table
  end
end

prepare_database

TestMigration = OnlineMigrations::Utils.migration_parent
TestMigration.version = 20200101000001

OnlineMigrations.configure do |config|
  config.background_migrations.migrations_module = "BackgroundMigrations"

  # Do not waste time sleeping in tests
  config.background_migrations.batch_pause = 0.seconds
  config.background_migrations.sub_batch_pause_ms = 0

  # Active Record 5.1 changed the default primary and foreign key type to bigint.
  # In order to avoid specifying explicitly primary key types in migrations in tests,
  # disable this check and enable only where necessary.
  config.disable_check(:short_primary_key_type)
end

require_relative "support/schema"
require_relative "support/minitest_helpers"
require_relative "background_migrations/background_migrations"
