# frozen_string_literal: true

require "test_helper"

module SchemaStatements
  class CheckConstraintsTest < MiniTest::Test
    class Milestone < ActiveRecord::Base
    end

    attr_reader :connection

    def setup
      @connection = ActiveRecord::Base.connection

      @connection.create_table(:milestones, force: true) do |t|
        t.string :name
        t.text :description
        t.integer :points
      end

      Milestone.reset_column_information
    end

    def teardown
      connection.drop_table(:milestones) rescue nil
    end

    def test_add_check_constraint
      connection.add_check_constraint :milestones, "points >= 0"
      assert_raises(ActiveRecord::StatementInvalid) do
        Milestone.create!(points: -1)
      end
    end

    def test_add_check_constraint_when_exists
      connection.add_check_constraint :milestones, "points >= 0"
      connection.add_check_constraint :milestones, "points >= 0" # once again

      assert_raises(ActiveRecord::StatementInvalid) do
        Milestone.create!(points: -1)
      end
    end

    def test_add_unvalidated_check_constraint
      Milestone.create!(points: -1)

      connection.add_check_constraint :milestones, "points >= 0", validate: false

      assert_raises(ActiveRecord::StatementInvalid) do
        Milestone.create!(points: -1)
      end
    end

    def test_validate_check_constraint_by_name
      Milestone.create!(points: -1)

      connection.add_check_constraint :milestones, "points >= 0", name: "points_check", validate: false

      assert_raises(ActiveRecord::StatementInvalid) do
        connection.validate_check_constraint :milestones, name: "points_check"
      end

      Milestone.delete_all
      connection.validate_check_constraint :milestones, name: "points_check"

      assert_raises(ActiveRecord::StatementInvalid) do
        Milestone.create!(points: -1)
      end
    end

    def test_validate_check_constraint_by_expression
      Milestone.create!(points: -1)

      connection.add_check_constraint :milestones, "points >= 0", validate: false

      assert_raises(ActiveRecord::StatementInvalid) do
        connection.validate_check_constraint :milestones, expression: "points >= 0"
      end

      Milestone.delete_all
      connection.validate_check_constraint :milestones, expression: "points >= 0"

      assert_raises(ActiveRecord::StatementInvalid) do
        Milestone.create!(points: -1)
      end
    end

    def test_validate_non_existing_check_constraint
      error = assert_raises(ArgumentError) do
        connection.validate_check_constraint :milestones, name: "non_existing"
      end
      assert_match("has no check constraint", error.message)
    end
  end
end
