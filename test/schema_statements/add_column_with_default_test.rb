# frozen_string_literal: true

require "test_helper"

module SchemaStatements
  class AddColumnWithDefaultTest < Minitest::Test
    class Milestone < ActiveRecord::Base
    end

    attr_reader :connection

    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:milestones, force: :cascade)
      Milestone.reset_column_information
    end

    def teardown
      connection.drop_table(:milestones, if_exists: true)
    end

    def test_add_column_with_default
      connection.add_column_with_default(:milestones, :status, :integer, default: 0)

      Milestone.reset_column_information
      column = Milestone.columns_hash["status"]
      assert_equal 0, Integer(column.default)
      assert column.null
    end

    def test_add_column_with_default_disallow_nulls
      connection.add_column_with_default(:milestones, :status, :integer, default: 0, null: false)

      Milestone.reset_column_information
      assert_equal false, Milestone.columns_hash["status"].null
    end

    def test_add_column_with_default_updates_existing_records
      milestone = Milestone.create!

      connection.add_column_with_default(:milestones, :status, :integer, default: 0)
      assert_equal 0, milestone.reload.status
    end

    def test_add_column_with_default_expression
      connection.add_column_with_default(:milestones, :created_at, :datetime, default: -> { "now()" })

      Milestone.reset_column_information
      column = Milestone.columns_hash["created_at"]
      assert_equal "now()", column.default_function

      milestone = Milestone.create!
      assert_not_nil milestone.created_at
    end

    def test_add_column_with_default_quoted_expression
      connection.add_column_with_default(:milestones, :created_at, :datetime, default: -> { "'now()'" })

      Milestone.reset_column_information
      column = Milestone.columns_hash["created_at"]
      assert_nil column.default_function
      assert_not_nil column.default

      milestone = Milestone.create!
      assert_not_nil milestone.created_at
    end

    def test_add_column_with_default_disallow_nulls_creates_not_null_constraint
      connection.add_column_with_default(:milestones, :status, :integer, default: 0, null: false)
      Milestone.reset_column_information

      # Creates `NOT NULL` constraint on the column
      assert_not Milestone.columns_hash["status"].null
    end
  end
end
