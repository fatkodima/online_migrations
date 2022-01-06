# frozen_string_literal: true

require "test_helper"

module CommandChecker
  class IndexesTest < MiniTest::Test
    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users, force: :cascade) do |t|
        t.string :email
      end
    end

    def teardown
      @connection.drop_table(:users) rescue nil
    end

    class AddIndexNonConcurrently < TestMigration
      def change
        add_index :users, :email, unique: true
      end
    end

    def test_add_index_non_concurrently
      assert_unsafe AddIndexNonConcurrently, <<~MSG
        Adding an index non-concurrently blocks writes. Instead, use:

        class CommandChecker::IndexesTest::AddIndexNonConcurrently < #{migration_parent_string}
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

    class RemoveIndexNonConcurrently < TestMigration
      def change
        remove_index :users, :email
      end
    end

    def test_remove_index_non_concurrently
      assert_unsafe RemoveIndexNonConcurrently, <<~MSG
        Removing an index non-concurrently blocks writes. Instead, use:

        class CommandChecker::IndexesTest::RemoveIndexNonConcurrently < #{migration_parent_string}
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
  end
end
