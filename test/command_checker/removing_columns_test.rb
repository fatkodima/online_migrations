# frozen_string_literal: true

require "test_helper"

module CommandChecker
  class RemovingColumnsTest < MiniTest::Test
    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users, force: :cascade) do |t|
        t.string :name
        t.string :email, null: false
        t.timestamps(null: false)
      end

      @connection.create_table(:projects, force: :cascade) do |t|
        t.integer :user_id
        t.integer :attachable_id
        t.string :attachable_type
      end
    end

    def teardown
      @connection.drop_table(:users) rescue nil
      @connection.drop_table(:projects) rescue nil
    end

    class RemoveColumn < TestMigration
      def change
        remove_column :users, :email, :string, null: false
      end
    end

    def test_remove_column
      if ar_version >= 5
        assert_unsafe RemoveColumn, <<-MSG.strip_heredoc
          ActiveRecord caches database columns at runtime, so if you drop a column, it can cause exceptions until your app reboots.
          A safer approach is to:

          1. Ignore the column(s):

            class User < ApplicationRecord
              self.ignored_columns = ["email"]
            end

          2. Deploy
          3. Wrap column removing in a safety_assured { ... } block

            class CommandChecker::RemovingColumnsTest::RemoveColumn < #{migration_parent_string}
              def change
                safety_assured { remove_column :users, :email, :string, null: false }
              end
            end

          4. Remove columns ignoring
          5. Deploy
        MSG
      else
        assert_unsafe RemoveColumn, <<-MSG.strip_heredoc
          1. Ignore the column(s):

            class User < ActiveRecord::Base
              def self.columns
                super.reject { |c| ["email"].include?(c.name) }
              end
            end
        MSG
      end
    end

    class RemoveColumnNewTable < TestMigration
      def change
        create_table :users_new do |t|
          t.string :email
        end
        remove_column :users_new, :email, :string
      end
    end

    def test_remove_column_new_table
      assert_safe RemoveColumnNewTable
    end

    class RemoveColumnWithIndex < TestMigration
      def change
        safety_assured { add_index :users, :email }
        remove_column :users, :email, :string
      end
    end

    def test_remove_column_with_index
      assert_unsafe RemoveColumnWithIndex, <<-MSG.strip_heredoc
        Removing a column will automatically remove all of the indexes that involved the removed column.
        But the indexes would be removed non-concurrently, so you need to safely remove the indexes first:

        class CommandChecker::RemovingColumnsTest::RemoveColumnWithIndexRemoveIndexes < #{migration_parent_string}
          disable_ddl_transaction!

          def change
            remove_index :users, name: :index_users_on_email, algorithm: :concurrently
          end
        end
      MSG
    end

    class RemoveColumnWithCompoundIndex < TestMigration
      def change
        safety_assured do
          add_index :users, [:name, :email]
          add_index :users, :email
        end
        remove_column :users, :name
      end
    end

    def test_remove_column_with_compound_index
      assert_unsafe RemoveColumnWithCompoundIndex,
        "remove_index :users, name: :index_users_on_name_and_email, algorithm: :concurrently"
    end

    def test_remove_column_with_index_small_table
      OnlineMigrations.config.small_tables = [:users]

      assert_unsafe RemoveColumnWithIndex, "ActiveRecord caches database columns at runtime"
    ensure
      OnlineMigrations.config.small_tables.clear
    end

    class RemoveColumns < TestMigration
      def change
        remove_columns :users, :name, :email, type: :string
      end
    end

    def test_remove_columns
      if ar_version >= 5
        assert_unsafe RemoveColumns, 'self.ignored_columns = ["name", "email"]'
      else
        assert_unsafe RemoveColumns, 'super.reject { |c| ["name", "email"].include?(c.name) }'
      end
    end

    class RemoveColumnsNewTable < TestMigration
      def up
        create_table :users_new do |t|
          t.string :name
          t.string :email
        end
        remove_columns :users_new, :name, :email
      end

      def down
        drop_table :users_new
      end
    end

    def test_remove_columns_new_table
      assert_safe RemoveColumnsNewTable
    end

    class RemoveColummnsWithIndex < TestMigration
      def change
        safety_assured { add_index :users, :email }
        remove_columns :users, :name, :email
      end
    end

    def test_remove_columns_with_index
      assert_unsafe RemoveColummnsWithIndex, "remove_index :users, name: :index_users_on_email, algorithm: :concurrently"
    end

    class RemoveTimestamps < TestMigration
      def change
        remove_timestamps :users
      end
    end

    def test_remove_timestamps
      if ar_version >= 5
        assert_unsafe RemoveTimestamps, 'self.ignored_columns = ["created_at", "updated_at"]'
      else
        assert_unsafe RemoveTimestamps, 'super.reject { |c| ["created_at", "updated_at"].include?(c.name) }'
      end
    end

    class RemoveTimestampsNewTable < TestMigration
      def change
        create_table :users_new do |t|
          t.string :name
          t.timestamps(null: false)
        end
        remove_timestamps :users_new
      end
    end

    def test_remove_timestamps_new_table
      assert_safe RemoveTimestampsNewTable
    end

    class RemoveTimestampsWithIndex < TestMigration
      def change
        safety_assured { add_index :users, :created_at }
        remove_timestamps :users
      end
    end

    def test_remove_timestamps_with_index
      assert_unsafe RemoveTimestampsWithIndex, "remove_index :users, name: :index_users_on_created_at, algorithm: :concurrently"
    end

    class RemoveReference < TestMigration
      def change
        remove_reference :projects, :user
      end
    end

    def test_remove_reference
      if ar_version >= 5
        assert_unsafe RemoveReference, 'self.ignored_columns = ["user_id"]'
      else
        assert_unsafe RemoveReference, 'super.reject { |c| ["user_id"].include?(c.name) }'
      end
    end

    class RemovePolymorphicReference < TestMigration
      def change
        remove_reference :projects, :attachable, polymorphic: true
      end
    end

    def test_remove_polymorphic_reference
      if ar_version >= 5
        assert_unsafe RemovePolymorphicReference, 'self.ignored_columns = ["attachable_id", "attachable_type"]'
      else
        assert_unsafe RemovePolymorphicReference, 'super.reject { |c| ["attachable_id", "attachable_type"].include?(c.name) }'
      end
    end

    class RemoveReferenceNewTable < TestMigration
      def change
        create_table :projects_new do |t|
          t.references :user
        end
        remove_reference :projects_new, :user
      end
    end

    def test_remove_reference_new_table
      assert_safe RemoveReferenceNewTable
    end

    class RemoveReferenceWithIndex < TestMigration
      def change
        safety_assured { add_index :projects, :user_id }
        remove_reference :projects, :user
      end
    end

    def test_remove_reference_with_index
      assert_unsafe RemoveReferenceWithIndex, "remove_index :projects, name: :index_projects_on_user_id, algorithm: :concurrently"
    end

    class RemoveBelongsTo < TestMigration
      def change
        remove_belongs_to :projects, :user
      end
    end

    # remove_belongs_to is an alias for remove_reference, so it is covered by the latter
    def test_remove_belongs_to
      assert_unsafe RemoveBelongsTo
    end
  end
end
