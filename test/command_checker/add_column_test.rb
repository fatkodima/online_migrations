# frozen_string_literal: true

require "test_helper"

module CommandChecker
  class AddColumnTest < Minitest::Test
    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users, force: :cascade) do |t|
        t.string :email
      end
    end

    def teardown
      @connection.drop_table(:users, if_exists: true)
    end

    class AddColumnDefault < TestMigration
      def change
        add_column :users, :admin, :boolean, default: false
      end
    end

    def test_add_column_default
      assert_safe AddColumnDefault
    end

    class AddColumnDefaultNull < TestMigration
      def change
        add_column :users, :admin, :boolean, default: nil
      end
    end

    def test_add_column_default_null
      assert_safe AddColumnDefaultNull
    end

    class AddColumnVolatileUuidDefault < TestMigration
      def change
        # NOTE: Active Record accepts non-block (string) version for uuid
        add_column :users, :uuid_column, :uuid, default: "gen_random_uuid()"
      end
    end

    def test_add_column_volatile_uuid_default
      assert_unsafe AddColumnVolatileUuidDefault
    end

    class AddColumnNonVolatileUuidDefault < TestMigration
      def change
        add_column :users, :uuid_column, :uuid, default: "non_volatile"
      end
    end

    def test_add_column_non_volatile_uuid_default
      assert_safe AddColumnNonVolatileUuidDefault
    end

    class AddColumnVolatileDefault < TestMigration
      def change
        add_column :users, :random_value, :integer, default: -> { "1 + random()" }
      end
    end

    def test_add_column_volatile_default
      assert_unsafe AddColumnVolatileDefault, <<~MSG
        Adding a column with a non-null default blocks reads and writes while the entire table is rewritten.

        A safer approach is to:
        1. add the column without a default value
        2. change the column default
        3. backfill existing rows with the new value
      MSG
    end

    class AddColumnNonVolatileDefault < TestMigration
      def change
        # NOTE: value is treated as a simple string
        add_column :users, :random_value, :string, default: "random()"
      end
    end

    def test_add_column_non_volatile_default
      assert_safe AddColumnNonVolatileDefault
    end

    class AddColumnDefaultNotNull < TestMigration
      def change
        add_column :users, :admin, :boolean, default: false, null: false
      end
    end

    def test_add_column_default_not_null
      assert_safe AddColumnDefaultNotNull
    end

    class AddColumnNoDefault < TestMigration
      def change
        add_column :users, :age, :integer
      end
    end

    def test_add_column_no_default
      assert_safe AddColumnNoDefault
    end

    class AddColumnDefaultSafe < TestMigration
      def change
        add_column :users, :admin, :boolean
        change_column_default :users, :admin, from: nil, to: false
      end
    end

    def test_add_column_default_safe
      assert_safe AddColumnDefaultSafe
    end

    class AddColumnDefaultNewTable < TestMigration
      def change
        create_table :users_new
        add_column :users_new, :admin, :boolean, default: false
      end
    end

    def test_add_column_default_new_table
      assert_safe AddColumnDefaultNewTable
    end

    class AddColumnJson < TestMigration
      def change
        add_column :projects, :settings, :json
      end
    end

    def test_add_column_json
      assert_unsafe AddColumnJson, <<~MSG
        There's no equality operator for the json column type, which can cause errors for
        existing SELECT DISTINCT queries in your application. Use jsonb instead.

        class CommandChecker::AddColumnTest::AddColumnJson < #{migration_parent}
          def change
            add_column :projects, :settings, :jsonb
          end
        end
      MSG
    end

    class AddColumnJsonb < TestMigration
      def change
        add_column :users, :settings, :jsonb
      end
    end

    def test_add_column_jsonb
      assert_safe AddColumnJsonb
    end

    class AddColumnWithDefaultJson < TestMigration
      def change
        add_column_with_default :projects, :settings, :json, default: {}
      end
    end

    def test_add_column_with_default_json
      assert_unsafe AddColumnWithDefaultJson, <<~MSG
        There's no equality operator for the json column type, which can cause errors for
        existing SELECT DISTINCT queries in your application. Use jsonb instead.

        class CommandChecker::AddColumnTest::AddColumnWithDefaultJson < #{migration_parent}
          def change
            add_column_with_default :projects, :settings, :jsonb, default: {}
          end
        end
      MSG
    end

    class AddColumnWithDefaultJsonb < TestMigration
      def change
        add_column_with_default :users, :settings, :jsonb, default: {}
      end
    end

    def test_add_column_with_default_jsonb
      assert_safe AddColumnWithDefaultJsonb
    end

    class AddColumnGeneratedStored < TestMigration
      def change
        add_column :users, :lower_email, :virtual, type: :string, as: "LOWER(email)", stored: true
      end
    end

    def test_generated_stored
      assert_unsafe AddColumnGeneratedStored, <<~MSG
        Adding a stored generated column blocks reads and writes while the entire table is rewritten.
        Add a non-generated column and use callbacks or triggers instead.
      MSG
    end
  end
end
