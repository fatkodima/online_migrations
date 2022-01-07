# frozen_string_literal: true

require "test_helper"

module CommandChecker
  class AddColumnTest < MiniTest::Test
    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users, force: :cascade)
    end

    def teardown
      @connection.drop_table(:users) rescue nil
    end

    class AddColumnDefault < TestMigration
      def change
        add_column :users, :admin, :boolean, default: false
      end
    end

    def test_add_column_default
      with_target_version(11) do
        assert_safe AddColumnDefault
      end
    end

    def test_add_column_default_before_11
      with_target_version(10) do
        assert_unsafe AddColumnDefault, <<~MSG
          Adding a column with a non-null default blocks reads and writes while the entire table is rewritten.

          A safer approach is to:
          1. add the column without a default value
          2. change the column default
          3. backfill existing rows with the new value

          add_column_with_default takes care of all this steps:

          class CommandChecker::AddColumnTest::AddColumnDefault < #{migration_parent_string}
            disable_ddl_transaction!

            def change
              add_column_with_default :users, :admin, :boolean, default: false
            end
          end
        MSG
      end
    end

    class AddColumnVolatileUuidDefault < TestMigration
      def change
        # NOTE: ActiveRecord accepts non-block (string) version for uuid
        add_column :users, :uuid_column, :uuid, default: "gen_random_uuid()"
      end
    end

    def test_add_column_volatile_uuid_default
      with_target_version(11) do
        assert_unsafe AddColumnVolatileUuidDefault
      end
    end

    class AddColumnNonVolatileUuidDefault < TestMigration
      def change
        add_column :users, :uuid_column, :uuid, default: "non_volatile"
      end
    end

    def test_add_column_non_volatile_uuid_default
      with_target_version(11) do
        assert_safe AddColumnNonVolatileUuidDefault
      end
    end

    class AddColumnVolatileDefault < TestMigration
      def change
        add_column :users, :random_value, :integer, default: -> { "1 + random()" }
      end
    end

    def test_add_column_volatile_default
      with_target_version(11) do
        assert_unsafe AddColumnVolatileDefault
      end
    end

    class AddColumnNonVolatileDefault < TestMigration
      def change
        # NOTE: value is treated as a simple string
        add_column :users, :random_value, :string, default: "random()"
      end
    end

    def test_add_column_non_volatile_default
      with_target_version(11) do
        assert_safe AddColumnNonVolatileDefault
      end
    end

    class AddColumnDefaultNotNull < TestMigration
      def change
        add_column :users, :admin, :boolean, default: false, null: false
      end
    end

    def test_add_column_default_not_null_older_version
      with_target_version(10) do
        assert_unsafe AddColumnDefaultNotNull, "add the NOT NULL constraint"
      end
    end

    def test_add_column_default_not_null_newer_version
      with_target_version(11) do
        assert_safe AddColumnDefaultNotNull
      end
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
  end
end
