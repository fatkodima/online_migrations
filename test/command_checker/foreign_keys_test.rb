# frozen_string_literal: true

require "test_helper"

module CommandChecker
  class ForeignKeysTest < Minitest::Test
    def setup
      @connection = ActiveRecord::Base.connection

      @connection.create_table(:users, force: :cascade) do |t|
        t.string :name
      end

      @connection.create_table(:repositories, force: :cascade)

      @connection.create_table(:projects, force: :cascade) do |t|
        t.string :name
        t.bigint :user_id
      end
    end

    def teardown
      @connection.drop_table(:projects, if_exists: true)
      @connection.drop_table(:users, if_exists: true)
    end

    class AddForeignKey < TestMigration
      def change
        add_foreign_key :projects, :users
      end
    end

    def test_add_foreign_key
      assert_unsafe AddForeignKey, <<~MSG
        Adding a foreign key blocks writes on both tables. Instead, add the foreign key without validating existing rows,
        then validate them in a separate migration.

        class CommandChecker::ForeignKeysTest::AddForeignKey < #{migration_parent}
          def change
            add_foreign_key :projects, :users, validate: false
          end
        end

        class ValidateCommandChecker::ForeignKeysTest::AddForeignKey < #{migration_parent}
          def change
            validate_foreign_key :projects, :users
          end
        end
      MSG
    end

    class AddForeignKeyValidate < TestMigration
      def change
        add_foreign_key :projects, :users, validate: true
      end
    end

    def test_add_foreign_key_validate
      assert_unsafe AddForeignKeyValidate
    end

    class AddForeignKeyNoValidate < TestMigration
      def change
        add_foreign_key :projects, :users, validate: false
      end
    end

    def test_add_foreign_key_no_validate
      assert_safe AddForeignKeyNoValidate
    end

    def test_add_foreign_key_no_validate_is_idempotent
      assert_empty @connection.foreign_keys(:projects)

      migrate AddForeignKeyNoValidate
      migrate AddForeignKeyNoValidate

      assert_equal 1, @connection.foreign_keys(:projects).size
    end

    class AddForeignKeyFromNewTable < TestMigration
      def change
        create_table :posts_new do |t|
          t.integer :user_id
        end
        add_foreign_key :posts_new, :users
      end
    end

    def test_add_foreign_key_one_new_table
      assert_safe AddForeignKeyFromNewTable
    end

    class AddForeignKeyValidateSameTransaction < TestMigration
      def change
        add_foreign_key :projects, :users, validate: false
        validate_foreign_key :projects, :users
      end
    end

    def test_add_foreign_key_validate_same_transaction
      assert_unsafe AddForeignKeyValidateSameTransaction, <<~MSG
        Validating a foreign key while holding heavy locks on tables is dangerous.
        Use disable_ddl_transaction! or a separate migration.
      MSG
    end

    class AddForeignKeyValidateNoTransaction < TestMigration
      disable_ddl_transaction!

      def change
        add_foreign_key :projects, :users, validate: false
        validate_foreign_key :projects, :users
      end
    end

    def test_add_foreign_key_validate_no_transaction
      assert_safe AddForeignKeyValidateNoTransaction
    end

    class HeavyLockAndValidateForeignKeySameTableInTransaction < TestMigration
      def change
        safety_assured { rename_column :projects, :name, :title }
        validate_foreign_key :projects, :users
      end
    end

    def test_heavy_lock_and_validate_foreign_key_same_table_in_transaction
      assert_unsafe HeavyLockAndValidateForeignKeySameTableInTransaction
    end

    class HeavyLockAndValidateForeignKeyDifferentTablesInTransaction < TestMigration
      def change
        safety_assured { rename_column :users, :name, :first_name }
        validate_foreign_key :projects, :users
      end
    end

    def test_heavy_lock_and_validate_foreign_key_different_tables_in_transaction
      assert_unsafe HeavyLockAndValidateForeignKeyDifferentTablesInTransaction
    end

    class CreateTableMultipleFks < TestMigration
      def change
        create_table :user_posts do |t|
          t.references :user, foreign_key: true
          t.bigint :project_id

          t.foreign_key :projects
        end
      end
    end

    def test_create_table_with_multiple_fks
      assert_unsafe CreateTableMultipleFks, "Adding multiple foreign keys"
    end

    class CreateTableOneFk < TestMigration
      def change
        create_table :user_posts do |t|
          t.references :user, foreign_key: true
        end
      end
    end

    def test_create_table_one_fk
      assert_safe CreateTableOneFk
    end

    class MultipleFks < TestMigration
      def change
        create_table :user_posts do |t|
          t.references :user, foreign_key: true # references old table
          t.bigint :projects
        end

        add_foreign_key :user_posts, :projects # references old table
      end
    end

    def test_create_multiple_fks
      assert_unsafe MultipleFks, "Adding multiple foreign keys"
    end

    class MultipleFksAndNewTables < TestMigration
      def change
        create_table :parents
        create_table :children do |t|
          t.belongs_to :parent, foreign_key: true # references new table
        end

        add_foreign_key :projects, :users, validate: false # references old table
      end
    end

    def test_multiple_fks_and_new_tables
      assert_safe MultipleFksAndNewTables
    end

    class AddReferenceColumn < TestMigration
      def change
        add_column :projects, :repository_id, :integer
      end
    end

    def test_add_reference_column
      assert_unsafe AddReferenceColumn, <<~MSG
        projects.repository_id references a column of different type - foreign keys should be of the same type as the referenced primary key.
        Otherwise, there's a risk of errors caused by IDs representable by one type but not the other.
      MSG
    end

    class AddReferenceColumnWithDefault < TestMigration
      def change
        add_column_with_default :projects, :repository_id, :integer, default: 1
      end
    end

    def test_add_reference_column_with_default
      assert_unsafe AddReferenceColumnWithDefault, <<~MSG
        projects.repository_id references a column of different type - foreign keys should be of the same type as the referenced primary key.
        Otherwise, there's a risk of errors caused by IDs representable by one type but not the other.
      MSG
    end

    class AddReferenceColumnNonExistentTable < TestMigration
      def change
        add_column :projects, :some_service_id, :integer
      end
    end

    def test_add_reference_column_non_existent_table
      assert_safe AddReferenceColumnNonExistentTable
    end

    class AddReferenceColumnIntegerWithLimit < TestMigration
      def change
        add_column :projects, :repository_id, :integer, limit: 8 # bigint
      end
    end

    def test_add_reference_column_integer_with_limit
      assert_safe AddReferenceColumnIntegerWithLimit
    end

    class AddReference < TestMigration
      def change
        add_reference :projects, :repository, type: :integer, index: false
      end
    end

    def test_add_reference
      assert_unsafe AddReference, "projects.repository_id references a column of different type"
    end

    class AddReferencePolymorphic < TestMigration
      def change
        add_reference :projects, :repository, type: :integer, polymorphic: true, index: false
      end
    end

    def test_add_reference_polymorphic
      assert_safe AddReferencePolymorphic
    end
  end
end
