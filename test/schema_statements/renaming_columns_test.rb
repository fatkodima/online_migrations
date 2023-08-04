# frozen_string_literal: true

require "test_helper"

module SchemaStatements
  class RenamingColumnsTest < Minitest::Test
    class User < ActiveRecord::Base
    end

    def setup
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

      # For Active Record 5.0+ we can use if_exists: true for drop_table
      @connection.drop_table(:users_column_rename) rescue nil
    end

    def test_column_is_not_renamed
      column_renames("fname" => "first_name")

      User.reset_column_information
      @schema_cache.clear!

      assert_equal :string, User.columns_hash["fname"].type
    end

    def test_rename_column_while_old_code_is_running
      column_renames("fname" => "first_name")

      @schema_cache.clear!
      User.reset_column_information

      # Fill the SchemaCache
      User.columns_hash
      User.primary_key

      # Need to run SQL directly, because rename_table
      # used in initialize_column_rename clears SchemaCache
      @connection.execute("ALTER TABLE users RENAME TO users_column_rename")
      @connection.execute("CREATE VIEW users AS SELECT *, fname AS first_name FROM users_column_rename")

      user = User.create!(fname: "John")
      assert user.persisted?
      assert_equal "John", user.fname
    end

    def test_old_code_reloads_after_rename_column
      column_renames("fname" => "first_name")

      # Need to run SQL directly, because rename_table
      # used in initialize_column_rename clears SchemaCache
      @connection.execute("ALTER TABLE users RENAME TO users_column_rename")
      @connection.execute("CREATE VIEW users AS SELECT *, fname AS first_name FROM users_column_rename")

      @schema_cache.clear!
      User.reset_column_information

      user = User.create!(fname: "John")
      assert user.persisted?
      assert_equal "John", user.fname
    end

    def test_old_code_uses_original_table_for_metadata
      column_renames("fname" => "first_name")

      @connection.initialize_column_rename(:users, :fname, :first_name)
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
      column_renames("fname" => "first_name")

      User.reset_column_information
      @schema_cache.clear!

      # Fill the SchemaCache
      User.columns_hash
      User.primary_key

      # Need to run SQL directly, because rename_table
      # used in initialize_column_rename clears SchemaCache
      @connection.execute("ALTER TABLE users RENAME TO users_column_rename")
      @connection.execute("CREATE VIEW users AS SELECT *, fname AS first_name FROM users_column_rename")

      user_old = User.create!(fname: "John")
      assert_equal User.last.id, user_old.id
      assert_equal "John", user_old.fname
    end

    def test_new_code_accepts_crud_operations
      column_renames("fname" => "first_name")

      @connection.initialize_column_rename(:users, :fname, :first_name)
      User.reset_column_information
      @schema_cache.clear!

      user = User.create!(first_name: "John")
      assert_equal User.last.id, user.id
      assert_equal "John", user.first_name
    end

    def test_revert_initialize_column_rename
      column_renames("fname" => "first_name")

      @connection.initialize_column_rename(:users, :fname, :first_name)

      assert_sql(
        'DROP VIEW "users"',
        'ALTER TABLE "users_column_rename" RENAME TO "users"'
      ) do
        @connection.revert_initialize_column_rename(:users)
      end
    end

    def test_revert_initialize_columns_rename
      column_renames("fname" => "first_name", "lname" => "last_name")

      @connection.initialize_columns_rename(:users, { fname: :first_name, lname: :last_name })

      assert_sql(
        'DROP VIEW "users"',
        'ALTER TABLE "users_column_rename" RENAME TO "users"'
      ) do
        @connection.revert_initialize_columns_rename(:users)
      end
    end

    def test_finalize_column_rename
      column_renames("fname" => "first_name")

      @connection.initialize_column_rename(:users, :fname, :first_name)

      assert_sql(
        'DROP VIEW "users"',
        'ALTER TABLE "users_column_rename" RENAME TO "users"',
        'ALTER TABLE "users" RENAME COLUMN "fname" TO "first_name"'
      ) do
        @connection.finalize_column_rename(:users, :fname, :first_name)
      end
    end

    def test_finalize_columns_rename
      column_renames("fname" => "first_name", "lname" => "last_name")

      @connection.initialize_columns_rename(:users, { fname: :first_name, lname: :last_name })

      assert_sql(
        'DROP VIEW "users"',
        'ALTER TABLE "users_column_rename" RENAME TO "users"',
        'ALTER TABLE "users" RENAME COLUMN "fname" TO "first_name"',
        'ALTER TABLE "users" RENAME COLUMN "lname" TO "last_name"'
      ) do
        @connection.finalize_columns_rename(:users, { fname: :first_name, lname: :last_name })
      end
    end

    def test_revert_finalize_column_rename
      column_renames("fname" => "first_name")

      @connection.initialize_column_rename(:users, :fname, :first_name)
      @connection.finalize_column_rename(:users, :fname, :first_name)

      assert_sql(
        'ALTER TABLE "users" RENAME COLUMN "first_name" TO "fname"',
        'ALTER TABLE "users" RENAME TO "users_column_rename"',
        'CREATE VIEW "users" AS SELECT *, "fname" AS "first_name" FROM "users_column_rename"'
      ) do
        @connection.revert_finalize_column_rename(:users, :fname, :first_name)
      end
    end

    def test_revert_finalize_columns_rename
      column_renames("fname" => "first_name", "lname" => "last_name")

      @connection.initialize_columns_rename(:users, { fname: :first_name, lname: :last_name })
      @connection.finalize_columns_rename(:users, { fname: :first_name, lname: :last_name })

      assert_sql(
        'ALTER TABLE "users" RENAME COLUMN "first_name" TO "fname"',
        'ALTER TABLE "users" RENAME COLUMN "last_name" TO "lname"',
        'ALTER TABLE "users" RENAME TO "users_column_rename"',
        'CREATE VIEW "users" AS SELECT *, "fname" AS "first_name", "lname" AS "last_name" FROM "users_column_rename"'
      ) do
        @connection.revert_finalize_columns_rename(:users, { fname: :first_name, lname: :last_name })
      end
    end

    # Test that it is properly reset in rails tests using fixtures.
    def test_initialize_column_rename_and_resetting_sequence
      skip("Rails 4.2 is not working with newer PostgreSQL") if ar_version <= 4.2

      column_renames("fname" => "first_name")
      @connection.initialize_column_rename(:users, :fname, :first_name)

      @schema_cache.clear!
      User.reset_column_information

      _user1 = User.create!(id: 100_000, fname: "Old")
      @connection.reset_pk_sequence!("users")
      user2 = User.create!(fname: "New")
      assert_equal user2, User.last
    end

    private
      def column_renames(renames)
        OnlineMigrations.config.column_renames["users"] = renames
      end
  end
end
