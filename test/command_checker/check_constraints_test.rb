# frozen_string_literal: true

require "test_helper"

module CommandChecker
  class CheckConstraintsTest < Minitest::Test
    def setup
      @connection = ActiveRecord::Base.connection

      @connection.create_table(:users, force: :cascade) do |t|
        t.string :name
        t.string :email
      end

      @connection.create_table(:projects, force: :cascade) do |t|
        t.string :name
      end
    end

    def teardown
      @connection.drop_table(:users, if_exists: true)
      @connection.drop_table(:projects, if_exists: true)
    end

    class AddCheckConstraint < TestMigration
      def change
        add_check_constraint :users, "char_length(name) >= 1", name: "name_length_check"
      end
    end

    def test_add_check_constraint
      assert_unsafe AddCheckConstraint, <<~MSG
        Adding a check constraint blocks reads and writes while every row is checked.
        A safer approach is to add the check constraint without validating existing rows,
        and then validating them in a separate transaction.

        class CommandChecker::CheckConstraintsTest::AddCheckConstraint < #{migration_parent}
          disable_ddl_transaction!

          def change
            add_check_constraint :users, "char_length(name) >= 1", name: "name_length_check", validate: false
            validate_check_constraint :users, name: "name_length_check"
          end
        end
      MSG
    end

    class AddCheckConstraintImplicitName < TestMigration
      def change
        add_check_constraint :users, "char_length(name) >= 1"
      end
    end

    def test_add_check_constraint_implicit_name
      assert_unsafe AddCheckConstraintImplicitName, 'validate_check_constraint :users, name: "chk_rails_185c538411"'
    end

    class AddCheckConstraintValidate < TestMigration
      def change
        add_check_constraint :users, "char_length(name) >= 1", name: "name_length_check", validate: true
      end
    end

    def test_add_check_constraint_validate
      assert_unsafe AddCheckConstraintValidate
    end

    class AddCheckConstraintNoValidate < TestMigration
      def change
        add_check_constraint :users, "char_length(name) >= 1", name: "name_length_check", validate: false
      end
    end

    def test_add_check_constraint_no_validate
      assert_safe AddCheckConstraintNoValidate
    end

    class AddCheckConstraintNewTable < TestMigration
      def change
        create_table :users_new do |t|
          t.string :name
        end
        add_check_constraint :users_new, "char_length(name) >= 1", name: "name_length_check", validate: true
      end
    end

    def test_add_check_constraint_new_table
      assert_safe AddCheckConstraintNewTable
    end

    class AddCheckConstraintValidateSameTransaction < TestMigration
      def change
        add_check_constraint :users, "char_length(name) >= 1", name: "name_length_check", validate: false
        validate_check_constraint :users, name: "name_length_check"
      end
    end

    def test_add_check_constraint_validate_same_transaction
      assert_unsafe AddCheckConstraintValidateSameTransaction, <<~MSG
        Validating a constraint while holding heavy locks on tables is dangerous.
        Use disable_ddl_transaction! or a separate migration.
      MSG
    end

    class AddCheckConstraintValidateNoTransaction < TestMigration
      disable_ddl_transaction!

      def change
        add_check_constraint :users, "char_length(name) >= 1", name: "name_length_check", validate: false
        validate_check_constraint :users, name: "name_length_check"
      end
    end

    def test_add_check_constraint_validate_no_transaction
      assert_safe AddCheckConstraintValidateNoTransaction
    end

    class HeavyLockAndValidateCheckConstraintSameTableInTransaction < TestMigration
      def change
        safety_assured { rename_column :users, :email, :mail_address }
        validate_check_constraint :users, name: "name_length_check"
      end
    end

    def test_heavy_lock_and_validate_check_constraint_same_table_in_transaction
      assert_unsafe HeavyLockAndValidateCheckConstraintSameTableInTransaction
    end

    class HeavyLockAndValidateCheckConstraintDifferentTablesInTransaction < TestMigration
      def change
        safety_assured { rename_column :projects, :name, :title }
        validate_check_constraint :users, name: "name_length_check"
      end
    end

    def test_heavy_lock_and_validate_check_constraint_different_tables_in_transaction
      assert_unsafe HeavyLockAndValidateCheckConstraintDifferentTablesInTransaction
    end
  end
end
