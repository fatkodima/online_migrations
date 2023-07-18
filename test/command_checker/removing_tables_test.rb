# frozen_string_literal: true

require "test_helper"

module CommandChecker
  class RemovingTablesTest < MiniTest::Test
    def setup
      @connection = ActiveRecord::Base.connection

      @connection.create_table(:companies, force: :cascade)
      @connection.create_table(:users, force: :cascade)
      @connection.create_join_table(:companies, :users)
      @connection.create_table(:repositories, force: :cascade) do |t|
        t.references :user, foreign_key: true
      end

      @connection.create_table(:projects, force: :cascade) do |t|
        t.references :user, foreign_key: true
        t.references :repository, foreign_key: true
      end
    end

    def teardown
      @connection.drop_table(:projects) rescue nil
      @connection.drop_table(:repositories) rescue nil
      @connection.drop_join_table(:companies, :users) rescue nil
      @connection.drop_table(:users) rescue nil
      @connection.drop_table(:companies) rescue nil
    end

    class DropTable < TestMigration
      def change
        drop_table :users, force: :cascade
      end
    end

    def test_drop_table
      assert_safe DropTable
    end

    class DropJoinTable < TestMigration
      def change
        drop_join_table :companies, :users
      end
    end

    # Since drop_join_table is implemented through drop_table in CommandChecker,
    # it is already covered by other tests.
    def test_drop_join_table
      assert_safe DropJoinTable
    end

    class DropProjects < TestMigration
      def change
        drop_table :projects
      end
    end

    def test_drop_table_multiple_foreign_keys
      assert_unsafe DropProjects, <<-MSG.strip_heredoc
        Dropping a table with multiple foreign keys blocks reads and writes on all involved tables until migration is completed.
        Remove all the foreign keys first.
      MSG
    end

    class DropRepositories < TestMigration
      def change
        drop_table :repositories, force: :cascade
      end
    end

    def test_drop_table_single_foreign_key
      assert_safe DropRepositories
    end

    def test_drop_table_self_referencing_foreign_key
      # This is not working in Active Record 4.2 - add_reference ignores :to_table option
      # @connection.add_reference :repositories, :forked_repository, foreign_key: { to_table: :repositories }

      @connection.add_column :repositories, :forked_repository_id, :integer
      @connection.add_foreign_key :repositories, :repositories, column: :forked_repository_id

      assert_safe DropRepositories
    end
  end
end
