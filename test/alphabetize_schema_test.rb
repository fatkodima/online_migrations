# frozen_string_literal: true

require "stringio"
require_relative "test_helper"

class AlphabetizeSchemaTest < Minitest::Test
  def setup
    @connection = ActiveRecord::Base.connection
    @connection.create_table(:users, force: true) do |t|
      t.string :name
      t.string :city
    end
  end

  def teardown
    @connection.drop_table(:users, if_exists: true)
  end

  def test_default
    # Columns are sorted in rails 8.1 (https://github.com/rails/rails/pull/53281).
    skip if ar_version >= 8.1

    schema = dump_schema

    expected_columns = <<-RUBY
    t.string "name"
    t.string "city"
    RUBY
    assert_match expected_columns, schema
  end

  def test_enabled
    schema = OnlineMigrations.config.stub(:alphabetize_schema, true) do
      dump_schema
    end

    expected_columns = <<-RUBY
    t.string "city"
    t.string "name"
    RUBY
    assert_match expected_columns, schema
  end

  private
    def dump_schema
      io = StringIO.new
      if OnlineMigrations::Utils.ar_version >= 7.2
        ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection.pool, io)
      else
        ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection, io)
      end
      io.string
    end
end
