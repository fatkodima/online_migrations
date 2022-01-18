# frozen_string_literal: true

require "test_helper"

module CommandChecker
  class AddTimestampsTest < MiniTest::Test
    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users, force: :cascade)
    end

    def teardown
      @connection.drop_table(:users) rescue nil
    end

    class AddTimestampsDefault < TestMigration
      def change
        add_timestamps :users, null: false, default: 3.days.ago # -> { "NOW()" }
      end
    end

    def test_add_timestamps_default
      with_target_version(11) do
        assert_safe AddTimestampsDefault
      end
    end

    def test_add_timestamps_default_before_11
      with_target_version(10) do
        assert_unsafe AddTimestampsDefault, <<-MSG.strip_heredoc
          Adding timestamps columns with non-null defaults blocks reads and writes while the entire table is rewritten.

          A safer approach is to, for both timestamps columns:
          1. add the column without a default value
          2. change the column default
          3. backfill existing rows with the new value
          4. add the NOT NULL constraint

          add_column_with_default takes care of all this steps:

          class CommandChecker::AddTimestampsTest::AddTimestampsDefault < #{migration_parent_string}
            disable_ddl_transaction!

            def change
              add_column_with_default :users, :created_at, :datetime, null: false, <paste value here>
              add_column_with_default :users, :updated_at, :datetime, null: false, <paste value here>
            end
          end
        MSG
      end
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
        add_timestamps :users_new, default: 3.days.ago
      end
    end

    def test_add_timestamps_default_new_table
      with_target_version(10) do
        assert_safe AddTimestampsDefaultNewTable
      end
    end
  end
end
