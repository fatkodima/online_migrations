# frozen_string_literal: true

require "test_helper"

module SchemaStatements
  class CheckConstraintsTest < Minitest::Test
    class Milestone < ActiveRecord::Base
    end

    attr_reader :connection

    def setup
      @connection = ActiveRecord::Base.connection

      @connection.create_table(:milestones, force: true) do |t|
        t.string :name
        t.text :description
        t.string :group
        t.integer :points
      end

      Milestone.reset_column_information
    end

    def teardown
      connection.drop_table(:milestones, if_exists: true)
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
      assert_raises(ArgumentError, "has no check constraint") do
        connection.validate_check_constraint :milestones, name: "non_existing"
      end
    end

    def test_remove_check_constraint
      connection.add_check_constraint :milestones, "points >= 0"
      assert_equal 1, connection.check_constraints(:milestones).size
      connection.remove_check_constraint :milestones, "points >= 0"
      assert_empty connection.check_constraints(:milestones)
    end

    def test_remove_check_constraint_when_not_exists
      assert_empty connection.check_constraints(:milestones)

      assert_nothing_raised do
        connection.remove_check_constraint :milestones, "points >= 0"
      end
    end

    def test_add_not_null_constraint
      milestone = Milestone.create!(name: nil)

      assert_raises(ActiveRecord::StatementInvalid) do
        connection.add_not_null_constraint :milestones, :name
      end

      milestone.destroy
      connection.add_not_null_constraint :milestones, :name

      assert_raises(ActiveRecord::StatementInvalid) do
        Milestone.create!(name: nil)
      end
    end

    def test_add_unvalidated_not_null_constraint
      Milestone.create!(name: nil)

      connection.add_not_null_constraint :milestones, :name, validate: false

      assert_raises(ActiveRecord::StatementInvalid) do
        Milestone.create!(name: nil)
      end
    end

    def test_add_not_null_constraint_custom_name
      connection.add_not_null_constraint :milestones, :name, name: "custom_check_name"

      assert_raises(ActiveRecord::StatementInvalid) do
        Milestone.create!(name: nil)
      end
    end

    def test_add_not_null_constraint_is_reentrant
      connection.add_not_null_constraint :milestones, :name, validate: false
      connection.add_not_null_constraint :milestones, :name, validate: false
    end

    def test_add_not_null_constraint_when_column_is_non_nullable
      connection.change_column_null :milestones, :name, false
      connection.add_not_null_constraint :milestones, :name, validate: false
      assert_not connection.send(:__not_null_constraint_exists?, :milestones, :name)
    end

    def test_add_not_null_constraint_to_non_nullable_column
      connection.change_column_null :milestones, :name, false

      Milestone.reset_column_information
      assert_equal false, Milestone.columns_hash["name"].null

      connection.add_not_null_constraint :milestones, :name

      Milestone.reset_column_information
      assert_equal false, Milestone.columns_hash["name"].null
    end

    def test_add_not_null_constraint_to_non_existent_table_raises
      assert_raises_with_message(ActiveRecord::StatementInvalid, "does not exist") do
        connection.add_not_null_constraint :non_existent, :name
      end
    end

    def test_add_not_null_constraint_to_column_named_like_keyword
      connection.add_not_null_constraint :milestones, :group

      assert_raises(ActiveRecord::StatementInvalid) do
        Milestone.create!(group: nil)
      end
    end

    def test_validate_not_null_constraint
      connection.add_not_null_constraint :milestones, :name, validate: false
      connection.validate_not_null_constraint :milestones, :name

      assert_raises(ActiveRecord::StatementInvalid) do
        Milestone.create!(name: nil)
      end
    end

    def test_validate_not_null_constraint_custom_name
      connection.add_not_null_constraint :milestones, :name, name: "custom_check_name", validate: false
      connection.validate_not_null_constraint :milestones, :name, name: "custom_check_name"

      assert_raises(ActiveRecord::StatementInvalid) do
        Milestone.create!(name: nil)
      end
    end

    def test_validate_non_existing_not_null_constraint_raises
      assert_raises(ArgumentError, "has no check constraint") do
        connection.validate_not_null_constraint :milestones, :name, name: "non_existing"
      end
    end

    def test_validate_non_existing_not_null_constraint_and_already_not_null_column_passes
      connection.change_column_null :milestones, :name, false

      assert_nothing_raised do
        connection.validate_not_null_constraint :milestones, :name, name: "non_existing"
      end
    end

    def test_remove_not_null_constraint
      connection.add_not_null_constraint :milestones, :name
      connection.remove_not_null_constraint :milestones, :name
      Milestone.create! # not raises
    end

    def test_add_text_limit_constraint
      milestone = Milestone.create!(description: "a" * 101)

      assert_raises(ActiveRecord::StatementInvalid) do
        connection.add_text_limit_constraint :milestones, :description, 100
      end

      milestone.destroy
      connection.add_text_limit_constraint :milestones, :description, 100

      assert_raises(ActiveRecord::StatementInvalid) do
        Milestone.create!(description: "a" * 101)
      end
    end

    def test_add_text_limit_constraint_to_not_text_column_raises
      assert_raises_with_message(RuntimeError, /add_text_limit_constraint must be used only with :text columns/) do
        connection.add_text_limit_constraint :milestones, :name, 100
      end
    end

    def test_add_unvalidated_text_limit_constraint
      Milestone.create!(description: "a" * 101)

      connection.add_text_limit_constraint :milestones, :description, 100, validate: false

      assert_raises(ActiveRecord::StatementInvalid) do
        Milestone.create!(description: "a" * 101)
      end
    end

    def test_add_text_limit_constraint_custom_name
      connection.add_text_limit_constraint :milestones, :description, 100, validate: false, name: "custom_check_name"
      connection.validate_text_limit_constraint :milestones, :description, name: "custom_check_name"

      assert_raises(ActiveRecord::StatementInvalid) do
        Milestone.create!(description: "a" * 101)
      end
    end

    def test_add_text_limit_constraint_is_reentrant
      connection.add_text_limit_constraint :milestones, :description, 100
      connection.add_text_limit_constraint :milestones, :description, 100
    end

    def test_validate_text_limit_constraint
      connection.add_text_limit_constraint :milestones, :description, 100, validate: false
      connection.validate_text_limit_constraint :milestones, :description

      assert_raises(ActiveRecord::StatementInvalid) do
        Milestone.create!(description: "a" * 101)
      end
    end

    def test_validate_non_existing_text_limit_constraint_raises
      assert_raises_with_message(ArgumentError, "has no check constraint") do
        connection.validate_text_limit_constraint :milestones, :description, name: "non_existing"
      end
    end

    def test_remove_text_limit_constraint
      connection.add_text_limit_constraint :milestones, :description, 100
      connection.remove_text_limit_constraint :milestones, :description
      Milestone.create!(description: "a" * 101) # not raises
    end
  end
end
