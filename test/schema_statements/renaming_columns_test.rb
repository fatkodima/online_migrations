# frozen_string_literal: true

require "test_helper"

module SchemaStatements
  class RenamingColumnsTest < MiniTest::Test
    class User < ActiveRecord::Base
    end

    def setup
      OnlineMigrations.config.column_renames["users"] = { "fname" => "first_name", "lname" => "last_name" }

      @connection = ActiveRecord::Base.connection
      @schema_cache = @connection.schema_cache

      @connection.create_table(:users, force: true) do |t|
        t.string :fname, index: true
        t.string :lname, index: true
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

      assert_equal :string, User.columns_hash["fname"].type
      assert_equal :string, User.columns_hash["lname"].type
    end

    def test_rename_column_while_old_code_is_running
      @schema_cache.clear!
      User.reset_column_information

      # Fill the SchemaCache
      User.columns_hash
      User.primary_key

      # Need to run SQL directly, because rename_table
      # used in initialize_columns_rename clears SchemaCache
      @connection.execute("ALTER TABLE users RENAME TO users_column_rename")
      @connection.execute("CREATE VIEW users AS SELECT *, fname AS first_name, lname AS last_name FROM users_column_rename")

      user = User.create!(fname: "First Name", lname: "Last Name")
      assert user.persisted?
      assert_equal "First Name", user.fname
      assert_equal "Last Name", user.lname
    end

    def test_old_code_reloads_after_rename_column
      # Need to run SQL directly, because rename_table
      # used in initialize_columns_rename clears SchemaCache
      @connection.execute("ALTER TABLE users RENAME TO users_column_rename")
      @connection.execute("CREATE VIEW users AS SELECT *, fname AS first_name, lname AS last_name FROM users_column_rename")

      @schema_cache.clear!
      User.reset_column_information

      user = User.create!(fname: "First Name", lname: "Last Name")
      assert user.persisted?
      assert_equal "First Name", user.fname
      assert_equal "Last Name", user.lname
    end

    def test_old_code_uses_original_table_for_metadata
      @connection.initialize_columns_rename(:users, {fname: :first_name, lname: :last_name})
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
      # used in initialize_columns_rename clears SchemaCache
      @connection.execute("ALTER TABLE users RENAME TO users_column_rename")
      @connection.execute("CREATE VIEW users AS SELECT *, fname AS first_name, lname AS last_name FROM users_column_rename")

      user_old = User.create!(fname: "First Name", lname: "Last Name")
      assert_equal User.last.id, user_old.id
      assert_equal "First Name", user_old.fname
      assert_equal "Last Name", user_old.lname
    end

    def test_new_code_accepts_crud_operations
      @connection.initialize_columns_rename(:users, {fname: :first_name, lname: :last_name})
      User.reset_column_information
      @schema_cache.clear!

      user = User.create!(first_name: "First Name", last_name: "Last Name")
      assert_equal User.last.id, user.id
      assert_equal "First Name", user.first_name
      assert_equal "Last Name", user.last_name
    end

    def test_revert_initialize_columns_rename
      @connection.initialize_columns_rename(:users, {fname: :first_name, lname: :last_name})

      assert_sql(
        'DROP VIEW "users"',
        'ALTER TABLE "users_column_rename" RENAME TO "users"'
      ) do
        @connection.revert_initialize_columns_rename(:users)
      end
    end

    def test_finalize_columns_rename
      @connection.initialize_columns_rename(:users, {fname: :first_name, lname: :last_name})

      assert_sql(
        'DROP VIEW "users"',
        'ALTER TABLE "users_column_rename" RENAME TO "users"',
        'ALTER TABLE "users" RENAME COLUMN "fname" TO "first_name"',
        'ALTER TABLE "users" RENAME COLUMN "lname" TO "last_name"'
      ) do
        @connection.finalize_columns_rename(:users, {fname: :first_name, lname: :last_name})
      end
    end

    def test_revert_finalize_columns_rename
      @connection.initialize_columns_rename(:users, {fname: :first_name, lname: :last_name})
      @connection.finalize_columns_rename(:users, {fname: :first_name, lname: :last_name})

      assert_sql(
        'ALTER TABLE "users" RENAME COLUMN "first_name" TO "fname"',
        'ALTER TABLE "users" RENAME COLUMN "last_name" TO "lname"',
        'ALTER TABLE "users" RENAME TO "users_column_rename"',
        'CREATE VIEW "users" AS SELECT *, "fname" AS "first_name", "lname" AS "last_name" FROM "users_column_rename"'
      ) do
        @connection.revert_finalize_columns_rename(:users, {fname: :first_name, lname: :last_name})
      end
    end

    # Test that it is properly reset in rails tests using fixtures.
    def test_initialize_columns_rename_and_resetting_sequence
      skip("Rails 4.2 is not working with newer PostgreSQL") if ar_version <= 4.2

      @connection.initialize_columns_rename(:users, {fname: :first_name, lname: :last_name})

      @schema_cache.clear!
      User.reset_column_information

      _user1 = User.create!(id: 100_000, first_name: "Old First", last_name: "Old Last")
      @connection.reset_pk_sequence!("users")
      user2 = User.create!(fname: "New First", lname: "New Last")
      assert_equal user2, User.last
    end
  end
end
