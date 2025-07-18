# frozen_string_literal: true

require "test_helper"

module CommandChecker
  class IndexesTest < Minitest::Test
    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users, force: :cascade) do |t|
        t.string :email
      end

      @connection.create_table(:projects, force: :cascade) do |t|
        t.string :name
        t.bigint :creator_id
        t.integer :status
        t.datetime :created_at
      end
    end

    def teardown
      @connection.drop_table(:users, if_exists: true)
      @connection.drop_table(:projects, if_exists: true)
    end

    class AddIndexNonConcurrently < TestMigration
      def change
        add_index :users, :email, unique: true
      end
    end

    def test_add_index_non_concurrently
      assert_unsafe AddIndexNonConcurrently, <<~MSG
        Adding an index non-concurrently blocks writes. Instead, use:

        class CommandChecker::IndexesTest::AddIndexNonConcurrently < #{migration_parent}
          disable_ddl_transaction!

          def change
            add_index :users, :email, unique: true, algorithm: :concurrently
          end
        end
      MSG
    end

    class AddIndexConcurrently < TestMigration
      disable_ddl_transaction!

      def change
        add_index :users, :email, algorithm: :concurrently
      end
    end

    def test_add_index_concurrently
      assert_safe AddIndexConcurrently
    end

    def test_add_index_concurrently_corruption
      with_target_version(14.3) do
        assert_unsafe AddIndexConcurrently, "can cause silent data corruption"
      end
    end

    class AddIndexNewTable < TestMigration
      def change
        create_table :users_new do |t|
          t.string :email
        end

        add_index :users_new, :email
      end
    end

    def test_add_index_new_table
      assert_safe AddIndexNewTable
    end

    class AddIndexNewJoinTable < TestMigration
      def change
        create_join_table :users, :projects
        add_index :projects_users, :user_id
      end
    end

    def test_add_index_new_join_table
      assert_safe AddIndexNewJoinTable
    end

    class RemoveIndexNonConcurrently < TestMigration
      def change
        remove_index :users, :email
      end
    end

    def test_remove_index_non_concurrently
      assert_unsafe RemoveIndexNonConcurrently, <<~MSG
        Removing an index non-concurrently blocks writes. Instead, use:

        class CommandChecker::IndexesTest::RemoveIndexNonConcurrently < #{migration_parent}
          disable_ddl_transaction!

          def change
            remove_index :users, column: :email, algorithm: :concurrently
          end
        end
      MSG
    end

    class RemoveIndexConcurrently < TestMigration
      disable_ddl_transaction!

      def change
        add_index :users, :email, algorithm: :concurrently
        remove_index :users, :email, algorithm: :concurrently
      end
    end

    def test_remove_index_concurrently
      assert_safe RemoveIndexConcurrently
    end

    class RemoveIndexNewTable < TestMigration
      def change
        create_table :users_new do |t|
          t.string :email, index: true
        end

        remove_index :users_new, column: :email
      end
    end

    def test_remove_index_new_table
      assert_safe RemoveIndexNewTable
    end

    class ReplaceIndex < TestMigration
      disable_ddl_transaction!

      def change
        remove_index :projects, :creator_id, algorithm: :concurrently
        add_index :projects, [:creator_id, :created_at], algorithm: :concurrently
      end
    end

    def test_replace_index
      @connection.add_index(:projects, :creator_id)

      assert_unsafe ReplaceIndex, <<~MSG
        Removing an old index before replacing it with the new one might result in slow queries while building the new index.
        A safer approach is to create the new index and then delete the old one.
      MSG
    end

    class ReplaceIndexCorrectOrder < TestMigration
      disable_ddl_transaction!

      def change
        add_index :projects, [:creator_id, :created_at], algorithm: :concurrently
        remove_index :projects, column: :creator_id, algorithm: :concurrently
      end
    end

    def test_replace_index_correct_order
      @connection.add_index(:projects, :creator_id)

      assert_safe ReplaceIndexCorrectOrder
    end

    class NonIntersectableIndexes < TestMigration
      disable_ddl_transaction!

      def change
        remove_index :projects, column: :creator_id, algorithm: :concurrently
        add_index :projects, :created_at, algorithm: :concurrently
      end
    end

    def test_non_intersectable_indexes
      assert_safe NonIntersectableIndexes
    end

    class ReplaceIndexCoveringIndexExists < TestMigration
      disable_ddl_transaction!

      def change
        remove_index :projects, column: :creator_id, algorithm: :concurrently
        add_index :projects, [:creator_id, :created_at], algorithm: :concurrently
      end
    end

    def test_replace_index_covering_index_exists
      @connection.add_index(:projects, :creator_id)
      @connection.add_index(:projects, [:creator_id, :id])

      assert_safe ReplaceIndexCoveringIndexExists
    end

    class ReplaceUniqueIndexCoveringIndexExists < TestMigration
      disable_ddl_transaction!

      def change
        remove_index :projects, column: :creator_id, algorithm: :concurrently
        add_index :projects, [:creator_id, :created_at], unique: true, algorithm: :concurrently
      end
    end

    def test_replace_unique_index_covering_index_exists
      @connection.add_index(:projects, :creator_id, unique: true)
      @connection.add_index(:projects, [:creator_id, :id], unique: true)

      assert_safe ReplaceUniqueIndexCoveringIndexExists
    end

    class ReplaceIndexAlmostCoveringIndexExists < TestMigration
      disable_ddl_transaction!

      def change
        remove_index :projects, column: :creator_id, algorithm: :concurrently
        add_index :projects, [:creator_id, :created_at], algorithm: :concurrently
      end
    end

    def test_replace_index_almost_covering_index_exists
      @connection.add_index(:projects, :creator_id)
      @connection.add_index(:projects, [:creator_id, :id], where: "status = 1") # "where" makes it non-covering

      assert_unsafe ReplaceIndexAlmostCoveringIndexExists, /removing an old index/i
    end
  end
end
