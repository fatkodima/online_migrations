# frozen_string_literal: true

require "test_helper"

module SchemaStatements
  class RenamingColumnTest < MiniTest::Test
    class User < ActiveRecord::Base
    end

    def setup
      OnlineMigrations.config.column_renames["users"] = { "name" => "first_name" }

      @connection = ActiveRecord::Base.connection
      @schema_cache = @connection.schema_cache

      @connection.create_table(:users, force: true) do |t|
        t.string :name, index: true
      end
    end

    def teardown
      # Reset table/column renames.
      OnlineMigrations.config.column_renames.clear
      @schema_cache.clear!

      @connection.execute("DROP VIEW users") rescue nil
      @connection.drop_table(:users) rescue nil

      # For ActiveRecord 5.0+ we can use if_exists: true for drop_table
      @connection.drop_table(:users_column_rename) rescue nil
    end

    def test_column_is_not_renamed
      User.reset_column_information
      @schema_cache.clear!

      assert_equal :string, User.columns_hash["name"].type
    end

    def test_rename_column_while_old_code_is_running
      @schema_cache.clear!
      User.reset_column_information

      # Fill the SchemaCache
      User.columns_hash
      User.primary_key

      # Need to run SQL directly, because rename_table
      # used in initialize_column_rename clears SchemaCache
      @connection.execute("ALTER TABLE users RENAME TO users_column_rename")
      @connection.execute("CREATE VIEW users AS SELECT *, name AS first_name FROM users_column_rename")

      user = User.create!(name: "Name")
      assert user.persisted?
      assert_equal "Name", user.name
    end

    def test_old_code_reloads_after_rename_column
      # Need to run SQL directly, because rename_table
      # used in initialize_column_rename clears SchemaCache
      @connection.execute("ALTER TABLE users RENAME TO users_column_rename")
      @connection.execute("CREATE VIEW users AS SELECT *, name AS first_name FROM users_column_rename")

      @schema_cache.clear!
      User.reset_column_information

      user = User.create!(name: "Name")
      assert user.persisted?
      assert_equal "Name", user.name
    end

    def test_old_code_uses_original_table_for_metadata
      @connection.initialize_column_rename(:users, :name, :first_name)
      User.reset_column_information
      @schema_cache.clear!

      assert_equal "id", User.primary_key

      refute_empty User.columns
      refute_empty User.columns_hash

      if ar_version >= 6.0
        refute_empty @schema_cache.indexes("users")
      end
    end

    def test_old_code_accepts_crud_operations
      User.reset_column_information
      @schema_cache.clear!

      # Fill the SchemaCache
      User.columns_hash
      User.primary_key

      # Need to run SQL directly, because rename_table
      # used in initialize_column_rename clears SchemaCache
      @connection.execute("ALTER TABLE users RENAME TO users_column_rename")
      @connection.execute("CREATE VIEW users AS SELECT *, name AS first_name FROM users_column_rename")

      user_old = User.create!(name: "Name")
      assert_equal User.last.id, user_old.id
      assert_equal "Name", user_old.name
    end

    def test_new_code_accepts_crud_operations
      @connection.initialize_column_rename(:users, :name, :first_name)
      User.reset_column_information
      @schema_cache.clear!

      user = User.create!(first_name: "Name")
      assert_equal User.last.id, user.id
      assert_equal "Name", user.first_name
    end

    def test_revert_initialize_column_rename
      @connection.initialize_column_rename(:users, :name, :first_name)

      assert_sql(
        'DROP VIEW "users"',
        'ALTER TABLE "users_column_rename" RENAME TO "users"'
      ) do
        @connection.revert_initialize_column_rename(:users)
      end
    end

    def test_finalize_column_rename
      @connection.initialize_column_rename(:users, :name, :first_name)

      assert_sql(
        'DROP VIEW "users"',
        'ALTER TABLE "users_column_rename" RENAME TO "users"',
        'ALTER TABLE "users" RENAME COLUMN "name" TO "first_name"'
      ) do
        @connection.finalize_column_rename(:users, :name, :first_name)
      end
    end

    def test_revert_finalize_column_rename
      @connection.initialize_column_rename(:users, :name, :first_name)
      @connection.finalize_column_rename(:users, :name, :first_name)

      assert_sql(
        'ALTER TABLE "users" RENAME COLUMN "first_name" TO "name"',
        'ALTER TABLE "users" RENAME TO "users_column_rename"',
        'CREATE VIEW "users" AS SELECT *, "name" AS "first_name" FROM "users_column_rename"'
      ) do
        @connection.revert_finalize_column_rename(:users, :name, :first_name)
      end
    end

    # Test that it is properly reset in rails tests using fixtures.
    def test_initialize_column_rename_and_resetting_sequence
      skip("Rails 4.2 is not working with newer PostgreSQL") if ar_version <= 4.2

      @connection.initialize_column_rename(:users, :name, :first_name)

      @schema_cache.clear!
      User.reset_column_information

      _user1 = User.create!(id: 100_000, name: "Old")
      @connection.reset_pk_sequence!("users")
      user2 = User.create!(name: "New")
      assert_equal user2, User.last
    end
  end
end
