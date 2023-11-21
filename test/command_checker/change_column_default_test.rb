# frozen_string_literal: true

require "test_helper"

module CommandChecker
  class ChangeColumnDefaultTest < Minitest::Test
    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users, force: :cascade) do |t|
        t.string :name
      end
    end

    def teardown
      @connection.drop_table(:users) rescue nil
    end

    class ChangeColumnDefault < TestMigration
      def change
        change_column_default :users, :name, from: nil, to: "Test"
      end
    end

    def test_with_partial_writes
      with_partial_writes(true) do
        if ar_version >= 7
          assert_unsafe ChangeColumnDefault, <<~MSG
            Partial writes are enabled, which can cause incorrect values
            to be inserted when changing the default value of a column.
            Disable partial writes in config/application.rb:

            config.active_record.partial_inserts = false
          MSG
        else
          assert_unsafe ChangeColumnDefault, <<~MSG
            config.active_record.partial_writes = false
          MSG
        end
      end
    end

    class ChangeColumnDefaultHash < TestMigration
      def change
        change_column_default :users, :name, from: nil, to: "Test"
      end
    end

    def test_with_partial_writes_hash
      with_partial_writes(true) do
        assert_unsafe ChangeColumnDefaultHash
      end
    end

    def test_no_partial_writes
      with_partial_writes(false) do
        assert_safe ChangeColumnDefault
      end
    end

    class ChangeColumnDefaultNewColumn < TestMigration
      def up
        add_column :users, :nice, :boolean
        change_column_default :users, :nice, true
      end

      def down
        remove_column :users, :nice
      end
    end

    def test_new_column
      with_partial_writes(true) do
        assert_safe ChangeColumnDefaultNewColumn
      end
    end
  end
end
