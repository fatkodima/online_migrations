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
  end
end
