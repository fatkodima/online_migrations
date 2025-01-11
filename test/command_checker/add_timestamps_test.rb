# frozen_string_literal: true

require "test_helper"

module CommandChecker
  class AddTimestampsTest < Minitest::Test
    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users, force: :cascade)
    end

    def teardown
      @connection.drop_table(:users, if_exists: true)
    end

    class AddTimestampsDefault < TestMigration
      def change
        add_timestamps :users, null: false, default: -> { "NOW()" }
      end
    end

    def test_add_timestamps_default
      assert_safe AddTimestampsDefault
    end

    class AddTimestampsVolatileDefault < TestMigration
      def change
        add_timestamps :users, null: false, default: -> { "NOW() + (random() * (interval '90 days'))" }
      end
    end

    def test_add_timestamps_volatile_default
      assert_unsafe AddTimestampsVolatileDefault, <<~MSG
        Adding timestamp columns with volatile defaults blocks reads and writes while the entire table is rewritten.

        A safer approach is to, for both timestamps columns:
        1. add the column without a default value
        2. change the column default
        3. backfill existing rows with the new value
        4. add the NOT NULL constraint

        add_column_with_default takes care of all this steps:

        class CommandChecker::AddTimestampsTest::AddTimestampsVolatileDefault < #{migration_parent}
          disable_ddl_transaction!

          def change
            add_column_with_default :users, :created_at, :datetime, null: false, <paste value here>
            add_column_with_default :users, :updated_at, :datetime, null: false, <paste value here>
          end
        end
      MSG
    end

    class AddTimestampsNoDefault < TestMigration
      def change
        add_timestamps :users, null: false
      end
    end

    def test_add_timestamps_no_default
      assert_safe AddTimestampsNoDefault
    end

    class AddTimestampsDefaultNewTable < TestMigration
      def change
        create_table :users_new
        add_timestamps :users_new, default: -> { "NOW()" }
      end
    end

    def test_add_timestamps_default_new_table
      assert_safe AddTimestampsDefaultNewTable
    end
  end
end
