# frozen_string_literal: true

require "test_helper"

module CommandChecker
  class MiscTest < MiniTest::Test
    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users, force: :cascade)
      @connection.create_table(:projects, force: :cascade)
    end

    def teardown
      @connection.drop_table(:projects) rescue nil
      @connection.drop_table(:users) rescue nil
    end

    class ForceCreateTable < TestMigration
      def change
        create_table :users, force: true
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

    def test_execute_query_safety_assured
      assert_safe ExecuteQuerySafetyAssured
    end
  end
end
