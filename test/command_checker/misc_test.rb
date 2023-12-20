# frozen_string_literal: true

require "test_helper"

module CommandChecker
  class MiscTest < Minitest::Test
    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users, force: :cascade) do |t|
        t.string :email
        t.decimal :credit_score, precision: 10, scale: 5
      end

      @connection.create_table(:projects, force: :cascade) do |t|
        t.bigint :user_id
        t.text :description
      end
    end

    def teardown
      @connection.drop_table(:projects, if_exists: true)
      @connection.drop_table(:users, if_exists: true)
    end

    class ForceCreateTable < TestMigration
      def change
        create_table :users, force: true
      end
    end

    def test_unsupported_database
      @connection.stub(:adapter_name, "MySQL") do
        assert_raises_with_message(StandardError, /MySQL is not supported/i) do
          migrate ForceCreateTable
        end
      end
    end

    def test_unsupported_version
      with_target_version(9.5) do
        assert_raises_with_message(StandardError, /PostgreSQL < 9.6 is not supported/i) do
          migrate ForceCreateTable
        end
      end
    end

    def test_force_create_table
      assert_unsafe ForceCreateTable
    end

    class ForceCreateJoinTable < TestMigration
      def change
        create_join_table :users, :projects, force: true
      end
    end

    def test_force_create_join_table
      assert_unsafe ForceCreateJoinTable
    end

    class CreateTable < TestMigration
      def change
        create_table :animals
      end
    end

    def test_create_table
      assert_safe CreateTable
    end

    class IntegerPrimaryKey < TestMigration
      def change
        create_table :animals, id: :integer
      end
    end

    def test_integer_primary_key
      OnlineMigrations.config.enable_check(:short_primary_key_type)

      assert_unsafe IntegerPrimaryKey, <<~MSG
        Using short integer types for primary keys is dangerous due to the risk of running
        out of IDs on inserts. Better to use one of 'bigint', 'bigserial' or 'uuid'.
      MSG
    ensure
      OnlineMigrations.config.disable_check(:short_primary_key_type)
    end

    class RenameTable < TestMigration
      def change
        rename_table :clients, :users
      end
    end

    def test_rename_table
      assert_unsafe RenameTable, <<~MSG
        Renaming a table that's in use will cause errors in your application.
        migration_helpers provides a safer approach to do this:

        1. Instruct Rails that you are going to rename a table:

          OnlineMigrations.config.table_renames = {
            "clients" => "users"
          }

        2. Deploy
        3. Tell the database that you are going to rename a table. This will not actually rename any tables,
        nor any data/indexes/foreign keys copying will be made, so will be very fast.
        It will use a VIEW to work with both table names simultaneously:

          class InitializeCommandChecker::MiscTest::RenameTable < #{migration_parent}
            def change
              initialize_table_rename :clients, :users
            end
          end

        4. Replace usages of the old table with a new table in the codebase
        5. Remove the table rename config from step 1
        6. Deploy
        7. Remove the VIEW created on step 3:

          class FinalizeCommandChecker::MiscTest::RenameTable < #{migration_parent}
            def change
              finalize_table_rename :clients, :users
            end
          end

        8. Deploy
      MSG
    end

    class RenameTableNewTable < TestMigration
      def change
        create_table :clients_new
        rename_table :clients_new, :users_new
      end
    end

    def test_rename_table_new_table
      assert_safe RenameTableNewTable
    end

    class ChangeTable < TestMigration
      def change
        change_table :users do |t|
          t.integer :new_column
        end
      end
    end

    def test_change_table
      assert_unsafe ChangeTable
    end

    class RenameColumn < TestMigration
      def change
        rename_column :users, :name, :first_name
      end
    end

    def test_rename_column
      assert_unsafe RenameColumn, <<~MSG
        Renaming a column that's in use will cause errors in your application.
        migration_helpers provides a safer approach to do this:

        1. Instruct Rails that you are going to rename a column:

          OnlineMigrations.config.column_renames = {
            "users" => {
              "name" => "first_name"
            }
          }

        2. Deploy
        3. Tell the database that you are going to rename a column. This will not actually rename any columns,
        nor any data/indexes/foreign keys copying will be made, so will be instantaneous.
        It will use a combination of a VIEW and column aliasing to work with both column names simultaneously:

          class InitializeCommandChecker::MiscTest::RenameColumn < #{migration_parent}
            def change
              initialize_column_rename :users, :name, :first_name
            end
          end

        4. Replace usages of the old column with a new column in the codebase
        5. Deploy
        6. Remove the column rename config from step 1
        7. Remove the VIEW created in step 3 and finally rename the column:

          class FinalizeCommandChecker::MiscTest::RenameColumn < #{migration_parent}
            def change
              finalize_column_rename :users, :name, :first_name
            end
          end

        8. Deploy
      MSG
    end

    def test_rename_column_without_partial_writes
      with_partial_writes(false) do
        assert_unsafe RenameColumn, <<~MSG
          1. Instruct Rails that you are going to rename a column:

            OnlineMigrations.config.column_renames = {
              "users" => {
                "name" => "first_name"
              }
            }

            NOTE: You also need to temporarily enable partial writes (is disabled by default in Active Record >= 7)
            until the process of column rename is fully done.
            # config/application.rb
            config.active_record.#{OnlineMigrations::Utils.ar_partial_writes_setting} = true
        MSG
      end
    end

    def test_rename_column_with_enumerate_columns_in_select_statements
      skip if ar_version < 7

      begin
        previous = ActiveRecord::Base.enumerate_columns_in_select_statements
        ActiveRecord::Base.enumerate_columns_in_select_statements = true

        assert_unsafe RenameColumn, <<~MSG
          5. Ignore old column

            self.ignored_columns = [:name]

          6. Deploy
          7. Remove the column rename config from step 1
          8. Remove the column ignore from step 5
          9. Remove the VIEW created in step 3 and finally rename the column:

            class FinalizeCommandChecker::MiscTest::RenameColumn < #{migration_parent}
              def change
                finalize_column_rename :users, :name, :first_name
              end
            end

          10. Deploy
        MSG
      ensure
        ActiveRecord::Base.enumerate_columns_in_select_statements = previous
      end
    end

    class RenameColumnNewTable < TestMigration
      def change
        create_table :users_new do |t|
          t.string :name
        end
        rename_column :users_new, :name, :first_name
      end
    end

    def test_rename_column_new_table
      assert_safe RenameColumnNewTable
    end

    class ValidateConstraint < TestMigration
      def change
        add_foreign_key :projects, :users, name: "projects_fk", validate: false
        validate_constraint :projects, "projects_fk"
      end
    end

    def test_validate_constraint
      assert_unsafe ValidateConstraint
    end

    class ValidateConstraintNoTransaction < TestMigration
      disable_ddl_transaction!

      def change
        add_foreign_key :projects, :users, name: "projects_fk", validate: false
        validate_constraint :projects, "projects_fk"
      end
    end

    def test_validate_constraint_no_transaction
      assert_safe ValidateConstraintNoTransaction
    end

    class ExecuteQuery < TestMigration
      def change
        execute("SELECT 1")
      end
    end

    def test_execute_query
      assert_unsafe ExecuteQuery, <<~MSG
        Online Migrations does not support inspecting what happens inside an
        execute call, so cannot help you here. Make really sure that what
        you're doing is safe before proceeding, then wrap it in a safety_assured { ... } block.
      MSG
    end

    class ExecuteQuerySafetyAssured < TestMigration
      def up
        safety_assured { execute("SELECT 1") }
      end

      def down; end
    end

    class ExecQuery < TestMigration
      def change
        exec_query "SELECT 1"
      end
    end

    def test_exec_query
      assert_unsafe ExecQuery
    end

    def test_execute_query_safety_assured
      assert_safe ExecuteQuerySafetyAssured
    end

    class AddUniqueConstraint < TestMigration
      def change
        add_unique_constraint :users, :email, name: "unique_email"
      end
    end

    def test_add_unique_constraint
      skip if ar_version < 7.1

      assert_unsafe AddUniqueConstraint, <<~MSG
        Adding a unique constraint blocks reads and writes while the underlying index is being built.
        A safer approach is to create a unique index first, and then create a unique constraint using that index.

        class CommandChecker::MiscTest::AddUniqueConstraintAddIndex < #{migration_parent}
          disable_ddl_transaction!

          def change
            add_index :users, :email, unique: true, name: "index_users_on_email", algorithm: :concurrently
          end
        end

        class CommandChecker::MiscTest::AddUniqueConstraint < #{migration_parent}
          def up
            add_unique_constraint :users, name: "unique_email", using_index: "index_users_on_email"
          end

          def down
            remove_unique_constraint :users, :email
          end
        end
      MSG
    end

    class AddUniqueConstraintUsingIndex < TestMigration
      def up
        add_unique_constraint :users, using_index: "index_users_on_email"
      end

      def down
        remove_unique_constraint :users, :email
      end
    end

    def test_add_unique_constraint_using_index
      skip if ar_version < 7.1

      @connection.add_index(:users, :email, unique: true, name: "index_users_on_email")
      assert_safe AddUniqueConstraintUsingIndex
    end

    class AddNotNullConstraint < TestMigration
      def change
        add_not_null_constraint :projects, :user_id
      end
    end

    def test_add_not_null_constraint
      assert_unsafe AddNotNullConstraint, <<~MSG
        Adding a NOT NULL constraint blocks reads and writes while every row is checked.
        A safer approach is to add the NOT NULL check constraint without validating existing rows,
        and then validating them in a separate migration.

        class CommandChecker::MiscTest::AddNotNullConstraint < #{migration_parent}
          def change
            add_not_null_constraint :projects, :user_id, validate: false
          end
        end

        class CommandChecker::MiscTest::AddNotNullConstraintValidate < #{migration_parent}
          def change
            validate_not_null_constraint :projects, :user_id
          end
        end
      MSG
    end

    class AddNotNullConstraintNoValidate < TestMigration
      def change
        add_not_null_constraint :projects, :user_id, validate: false
      end
    end

    def test_add_not_null_constraint_no_validate
      assert_safe AddNotNullConstraintNoValidate
    end

    class ValidateNotNullConstraint < TestMigration
      def change
        add_not_null_constraint :projects, :user_id, validate: false
        validate_not_null_constraint :projects, :user_id
      end
    end

    def test_validate_not_null_constraint
      assert_unsafe ValidateNotNullConstraint, <<~MSG
        Validating a constraint while holding heavy locks on tables is dangerous.
        Use disable_ddl_transaction! or a separate migration.
      MSG
    end

    class ValidateNotNullConstraintNoTransaction < TestMigration
      disable_ddl_transaction!

      def change
        add_not_null_constraint :projects, :user_id, validate: false
        validate_not_null_constraint :projects, :user_id
      end
    end

    def test_validate_not_null_constraint_no_transaction
      assert_safe ValidateNotNullConstraintNoTransaction
    end

    class AddTextLimitConstraint < TestMigration
      def change
        add_text_limit_constraint :projects, :description, 255
      end
    end

    def test_add_text_limit_constraint
      assert_unsafe AddTextLimitConstraint, <<~MSG
        Adding a limit on the text column blocks reads and writes while every row is checked.
        A safer approach is to add the limit check constraint without validating existing rows,
        and then validating them in a separate migration.

        class CommandChecker::MiscTest::AddTextLimitConstraint < #{migration_parent}
          def change
            add_text_limit_constraint :projects, :description, 255, validate: false
          end
        end

        class CommandChecker::MiscTest::AddTextLimitConstraintValidate < #{migration_parent}
          def change
            validate_text_limit_constraint :projects, :description
          end
        end
      MSG
    end

    class AddTextLimitConstraintNoValidate < TestMigration
      def change
        add_text_limit_constraint :projects, :description, 255, validate: false
      end
    end

    def test_add_text_limit_constraint_no_validate
      assert_safe AddTextLimitConstraintNoValidate
    end

    class ValidateTextLimitConstraint < TestMigration
      def change
        add_text_limit_constraint :projects, :description, 255, validate: false
        validate_text_limit_constraint :projects, :description
      end
    end

    def test_validate_text_limit_constraint
      assert_unsafe ValidateTextLimitConstraint, <<~MSG
        Validating a constraint while holding heavy locks on tables is dangerous.
        Use disable_ddl_transaction! or a separate migration.
      MSG
    end

    class ValidateTextLimitConstraintNoTransaction < TestMigration
      disable_ddl_transaction!

      def change
        add_text_limit_constraint :projects, :description, 255, validate: false
        validate_text_limit_constraint :projects, :description
      end
    end

    def test_validate_text_limit_constraint_no_transaction
      assert_safe ValidateTextLimitConstraintNoTransaction
    end

    class AddExclusionConstraint < TestMigration
      def change
        add_exclusion_constraint :users, "credit_score WITH =", using: :gist
      end
    end

    def test_add_exclusion_constraint
      skip if ar_version < 7.1

      assert_unsafe AddExclusionConstraint, "Adding an exclusion constraint blocks reads and writes while every row is checked."
    end

    class AddExclusionConstraintNewTable < TestMigration
      def change
        create_table :new_users do |t|
          t.decimal :credit_score, precision: 10, scale: 5
        end

        add_exclusion_constraint :new_users, "credit_score WITH =", using: :gist
      end
    end

    def test_add_exclusion_constraint_to_new_table
      skip if ar_version < 7.1

      assert_safe AddExclusionConstraintNewTable
    end

    class AddReferenceNoIndex < TestMigration
      def change
        add_reference :projects, :company, index: false
      end
    end

    class RevertAddReferenceNoIndex < TestMigration
      def change
        revert AddReferenceNoIndex
      end
    end

    class RevertAddReferenceNoIndexSafetyAssured < TestMigration
      def change
        safety_assured { revert AddReferenceNoIndex }
      end
    end

    def test_revert
      migrate AddReferenceNoIndex
      assert_unsafe RevertAddReferenceNoIndex
      assert_safe RevertAddReferenceNoIndexSafetyAssured
    end

    def test_prints_more_details_link
      assert_unsafe RenameColumn, <<~MSG
        8. Deploy

        For more details, see https://github.com/fatkodima/online_migrations#renaming-a-column
      MSG
    end
  end
end
