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
      connection.drop_table(:milestones) rescue nil
    end

    def test_add_column_with_default
      with_postgres(11) do
        connection.add_column_with_default(:milestones, :status, :integer, default: 0)

        Milestone.reset_column_information
        column = Milestone.columns_hash["status"]
        assert_equal "0", column.default
        assert column.null
      end
    end

    def test_add_column_with_default_disallow_nulls
      with_postgres(11) do
        connection.add_column_with_default(:milestones, :status, :integer, default: 0, null: false)

        Milestone.reset_column_information
        assert_equal false, Milestone.columns_hash["status"].null
      end
    end

    def test_add_column_with_default_updates_existing_records
      milestone = Milestone.create!

      with_postgres(11) do
        connection.add_column_with_default(:milestones, :status, :integer, default: 0)
        assert_equal 0, milestone.reload.status
      end
    end

    def test_add_column_with_default_expression
      with_postgres(10) do
        connection.add_column_with_default(:milestones, :created_at, :datetime, default: -> { "now()" })

        Milestone.reset_column_information
        column = Milestone.columns_hash["created_at"]
        assert_equal "now()", column.default_function

        milestone = Milestone.create!
        assert_not_nil milestone.created_at
      end
    end

    def test_add_column_with_default_quoted_expression
      with_postgres(10) do
        connection.add_column_with_default(:milestones, :created_at, :datetime, default: -> { "'now()'" })

        Milestone.reset_column_information
        column = Milestone.columns_hash["created_at"]
        assert_nil column.default_function
        assert_not_nil column.default

        milestone = Milestone.create!
        assert_not_nil milestone.created_at
      end
    end

    def test_add_column_with_default_raises_in_transaction_before_11
      with_postgres(10) do
        assert_raises_in_transaction do
          connection.add_column_with_default(:milestones, :status, :integer, default: 0)
        end
      end
    end

    def test_add_column_with_default_before_11
      with_postgres(10) do
        connection.add_column_with_default(:milestones, :status, :integer, default: 0)

        Milestone.reset_column_information
        column = Milestone.columns_hash["status"]
        assert_equal "0", column.default
        assert column.null
      end
    end

    def test_add_column_with_default_disallow_nulls_before_11_creates_not_null_check_constraint
      with_postgres(10) do
        connection.add_column_with_default(:milestones, :status, :integer, default: 0, null: false)
        Milestone.reset_column_information

        # Creates `NOT NULL` CHECK constraint on the table
        assert Milestone.columns_hash["status"].null
        assert_raises(ActiveRecord::StatementInvalid) do
          Milestone.create(status: nil)
        end
      end
    end

    def test_add_column_with_default_disallow_nulls_after_12_creates_not_null_constraint
      with_postgres(12) do
        connection.add_column_with_default(:milestones, :status, :integer, default: 0, null: false)
        Milestone.reset_column_information

        # Creates `NOT NULL` constraint on the column
        assert_not Milestone.columns_hash["status"].null
      end
    end

    def test_add_column_with_default_updates_existing_records_before_11
      milestone = Milestone.create!

      with_postgres(10) do
        connection.add_column_with_default(:milestones, :status, :integer, default: 0)

        Milestone.reset_column_information
        assert_equal 0, milestone.reload.status
      end
    end
  end
end
