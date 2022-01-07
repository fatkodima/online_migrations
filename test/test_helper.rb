# frozen_string_literal: true

require "online_migrations"

require "minitest/autorun"

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
  ActiveRecord::Migration.verbose = false
end

def prepare_database
  connection = ActiveRecord::Base.connection
  connection.tables.each do |table_name|
    connection.execute("DROP TABLE #{table_name} CASCADE")
  end

  ActiveRecord::SchemaMigration.create_table
end

prepare_database

require_relative "support/minitest_helpers"

TestMigration = OnlineMigrations::Utils.migration_parent
