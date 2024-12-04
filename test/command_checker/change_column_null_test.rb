# frozen_string_literal: true

require "test_helper"

module CommandChecker
  class ChangeColumnNullTest < Minitest::Test
    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users, force: :cascade) do |t|
        t.string :name
      end
    end

    def teardown
      @connection.drop_table(:users, if_exists: true)
    end

    class ChangeColumnNullToTrue < TestMigration
      def change
        change_column_null :users, :name, true
      end
    end

    def test_change_column_null_to_allow
      assert_safe ChangeColumnNullToTrue
    end

    class ChangeColumnNullToFalse < TestMigration
      def change
        change_column_null :users, :name, false
      end
    end

    def test_change_column_null_to_disallow_before_12
      with_target_version(11) do
        assert_unsafe ChangeColumnNullToFalse, <<~MSG
          Setting NOT NULL on an existing column blocks reads and writes while every row is checked.
          A safer approach is to add a NOT NULL check constraint and validate it in a separate transaction.
          add_not_null_constraint and validate_not_null_constraint take care of that.

          class CommandChecker::ChangeColumnNullTest::ChangeColumnNullToFalse < #{migration_parent}
            disable_ddl_transaction!

            def change
              add_not_null_constraint :users, :name, name: "users_name_null", validate: false
              # You can use `validate_constraint_in_background` if you have a very large table
              # and want to validate the constraint using background schema migrations.
              validate_not_null_constraint :users, :name, name: "users_name_null"
            end
          end
        MSG
      end
    end

    def test_change_column_null_to_disallow
      with_target_version(12) do
        assert_unsafe ChangeColumnNullToFalse, <<-MSG
    change_column_null :users, :name, false
    remove_check_constraint :users, name: "users_name_null"
        MSG
      end
    end

    class ChangeColumnNullToFalseDefault < TestMigration
      def change
        change_column_null :users, :name, false, "Guest"
      end
    end

    def test_change_column_null_to_disallow_default
      assert_unsafe ChangeColumnNullToFalseDefault, <<-MSG
    # Passing a default value to change_column_null runs a single UPDATE query,
    # which can cause downtime. Instead, backfill the existing rows in batches.
    update_column_in_batches(:users, :name, "Guest") do |relation|
      relation.where(name: nil)
    end
      MSG
    end

    class ChangeColumnNullNewTable < TestMigration
      def change
        create_table :users_new do |t|
          t.string :name
        end

        change_column_null :users_new, :name, false
      end
    end

    def test_change_column_null_new_table
      assert_safe ChangeColumnNullNewTable
    end

    class ChangeColumnNullConstraint < TestMigration
      def change
        safety_assured do
          add_not_null_constraint(:users, :name)
        end
        change_column_null :users, :name, false
      end
    end

    def test_change_column_null_constraint
      with_target_version(12) do
        assert_safe ChangeColumnNullConstraint
      end
    end

    def test_change_column_null_constraint_before_12
      with_target_version(11) do
        assert_unsafe ChangeColumnNullConstraint
      end
    end

    class ChangeColumnNullConstraintUnvalidated < TestMigration
      def change
        add_not_null_constraint(:users, :name, validate: false)
        change_column_null :users, :name, false
      end
    end

    def test_change_column_null_constraint_unvalidated
      with_target_version(12) do
        assert_unsafe ChangeColumnNullConstraintUnvalidated
      end
    end

    class ChangeColumnNullConstraintQuoted < TestMigration
      def up
        safety_assured do
          execute 'ALTER TABLE users ADD CONSTRAINT name_check CHECK ("name" IS NOT NULL)'
        end
        change_column_null :users, :name, false
      end

      def down
        execute "ALTER TABLE users DROP CONSTRAINT name_check"
        change_column_null :users, :name, true
      end
    end

    def test_change_column_null_constraint_quoted
      with_target_version(12) do
        assert_safe ChangeColumnNullConstraintQuoted
      end
    end
  end
end
