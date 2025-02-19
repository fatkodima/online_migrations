# frozen_string_literal: true

require "test_helper"

module SchemaStatements
  class IndexesTest < Minitest::Test
    def setup
      @connection = ActiveRecord::Base.connection

      @connection.create_table(:users, force: true) do |t|
        t.string :name
        t.bigint :company_id
      end
    end

    def teardown
      @connection.drop_table(:users, if_exists: true)
      OnlineMigrations::BackgroundSchemaMigrations::Migration.delete_all
    end

    def test_add_index
      @connection.add_index(:users, :name)
      assert @connection.index_exists?(:users, :name)
    end

    def test_add_index_concurrently_in_transaction
      assert_raises_in_transaction do
        @connection.add_index(:users, :name, algorithm: :concurrently)
      end
    end

    def test_add_index_when_exists
      @connection.add_index(:users, :name)
      @connection.add_index(:users, :name) # once again
      assert @connection.index_exists?(:users, :name)
    end

    def test_add_index_when_invalid_exists
      @connection.execute("INSERT INTO users (name) VALUES ('duplicate'), ('duplicate')")
      begin
        @connection.add_index(:users, :name, name: "name_idx", unique: true, algorithm: :concurrently)
      rescue ActiveRecord::RecordNotUnique
        # it raises, but invalid index is still created in the database
      end

      assert @connection.index_exists?(:users, :name, name: "name_idx", unique: true)
      assert_not index_valid?("name_idx")

      @connection.execute("DELETE FROM users")

      assert_sql(
        'DROP INDEX CONCURRENTLY "name_idx"',
        'CREATE UNIQUE INDEX CONCURRENTLY "name_idx"'
      ) do
        @connection.add_index(:users, :name, name: "name_idx", unique: true, algorithm: :concurrently)
      end
      assert index_valid?("name_idx")
    end

    def test_add_index_implicit_name
      @connection.add_index(:users, [:name, :company_id])
      assert @connection.index_exists?(:users, [:name, :company_id], name: "index_users_on_name_and_company_id")
    end

    def test_add_index_with_complex_expression
      expression = "(NAME::text)"
      @connection.add_index(:users, expression)
      assert_equal 1, @connection.indexes(:users).size

      @connection.add_index(:users, expression)
      assert_equal 1, @connection.indexes(:users).size
    end

    def test_remove_index
      @connection.add_index(:users, :name)
      assert @connection.index_exists?(:users, :name)
      @connection.remove_index(:users, :name)
      assert_not @connection.index_exists?(:users, :name)
    end

    def test_remove_index_by_name
      @connection.add_index(:users, :name)
      assert @connection.index_exists?(:users, :name)
      @connection.remove_index(:users, name: :index_users_on_name)
      assert_not @connection.index_exists?(:users, :name)
    end

    def test_remove_index_without_columns_and_name_provided
      assert_raises_with_message(ArgumentError, "No name or columns specified") do
        @connection.remove_index(:users)
      end
    end

    def test_remove_index_concurrently_in_transaction
      @connection.add_index(:users, :name)
      assert_raises_in_transaction do
        @connection.remove_index(:users, :name, algorithm: :concurrently)
      end
    end

    def test_remove_non_existing_index
      @connection.remove_index(:users, :name)
      assert_not @connection.index_exists?(:users, :name)
    end

    def test_remove_index_with_complex_expression
      expression = "(NAME::text)"
      @connection.add_index(:users, expression)
      assert_equal 1, @connection.indexes(:users).size

      @connection.remove_index(:users, expression)
      assert_empty @connection.indexes(:users)
    end

    def test_add_index_in_background
      @connection.add_index_in_background(:users, :name, unique: true, connection_class_name: "User")
      m = last_schema_migration

      assert_equal "index_users_on_name", m.name
      assert_equal "users", m.table_name
      assert_equal 'CREATE UNIQUE INDEX CONCURRENTLY "index_users_on_name" ON "users" ("name")', m.definition
    end

    def test_add_index_in_background_is_idempotent
      # Emulate created, but not yet executed, schema migration.
      OnlineMigrations.config.stub(:run_background_migrations_inline, -> { false }) do
        @connection.add_index_in_background(:users, :name, connection_class_name: "User")
      end

      @connection.add_index_in_background(:users, :name, connection_class_name: "User")
      assert_equal 1, OnlineMigrations::BackgroundSchemaMigrations::Migration.count
    end

    def test_add_index_in_background_when_different_index_with_same_name_already_exists
      @connection.add_index(:users, :name, unique: true)

      OnlineMigrations::Utils.stub(:multiple_databases?, false) do
        assert_raises_with_message(RuntimeError, /index with name 'index_users_on_name' already exists/i) do
          @connection.add_index_in_background(:users, :name, unique: true, where: "company_id", connection_class_name: "User")
        end
      end
      assert @connection.index_exists?(:users, :name)
      assert_equal 0, OnlineMigrations::BackgroundSchemaMigrations::Migration.count
    end

    def test_add_index_in_background_when_unfinished_migration_exists
      @connection.add_index(:users, :name, unique: true)

      OnlineMigrations::Utils.stub(:multiple_databases?, false) do
        assert_raises_with_message(RuntimeError, /index with name 'index_users_on_name' already exists/i) do
          @connection.add_index_in_background(:users, :name, unique: true, where: "company_id", connection_class_name: "User")
        end
      end
      assert @connection.index_exists?(:users, :name)
      assert_equal 0, OnlineMigrations::BackgroundSchemaMigrations::Migration.count
    end

    def test_add_index_in_background_when_using_multiple_databases
      # Enulate migration run on a primary shard. Now index exists on both tables.
      on_shard(:shard_one) do
        connection = Dog.connection
        assert_not connection.index_exists?(:dogs, :name)
        connection.add_index_in_background(:dogs, :name, unique: true, connection_class_name: "ShardRecord")
        assert connection.index_exists?(:dogs, :name)
      end

      on_shard(:shard_two) do
        # Emulate migration running on the second shard.
        connection = Dog.connection
        assert connection.index_exists?(:dogs, :name)
        connection.add_index_in_background(:dogs, :name, unique: true, connection_class_name: "ShardRecord")
        assert connection.index_exists?(:dogs, :name)
      end
    ensure
      on_each_shard { Dog.connection.remove_index(:dogs, :name) }
    end

    def test_add_index_in_background_custom_attributes
      @connection.add_index_in_background(:users, :name, name: "my_name", max_attempts: 5, statement_timeout: 10, connection_class_name: "User")
      m = last_schema_migration

      assert_equal "my_name", m.name
      assert_equal 5, m.max_attempts
      assert_equal 10, m.statement_timeout
    end

    def test_add_index_in_background_requires_connection_class_name_for_multiple_databases
      assert_raises_with_message(ArgumentError, /when using multiple databases/i) do
        @connection.add_index_in_background(:users, :name)
      end
    end

    def test_remove_index_in_background_raises_without_name
      @connection.add_index(:users, :name)
      assert_raises_with_message(ArgumentError, /Index name must be specified/i) do
        @connection.remove_index_in_background(:users, :name, name: nil, connection_class_name: "User")
      end
    end

    def test_remove_index_in_background_when_does_not_exist
      assert_raises_with_message(RuntimeError, /Index deletion was not enqueued/i) do
        OnlineMigrations::Utils.stub(:multiple_databases?, false) do
          @connection.remove_index_in_background(:users, :name, name: "index_users_on_name", connection_class_name: "User")
        end
      end

      assert_not @connection.index_exists?(:users, :name)
      assert_equal 0, OnlineMigrations::BackgroundSchemaMigrations::Migration.count
    end

    def test_remove_index_in_background_custom_attributes
      @connection.add_index(:users, :name)
      @connection.remove_index_in_background(:users, :name, name: "index_users_on_name", max_attempts: 5, statement_timeout: 10, connection_class_name: "User")
      m = last_schema_migration

      assert_equal "index_users_on_name", m.name
      assert_equal 5, m.max_attempts
      assert_equal 10, m.statement_timeout
    end

    def test_remove_index_in_background_requires_connection_class_name_for_multiple_databases
      @connection.add_index(:users, :name)

      assert_raises_with_message(ArgumentError, /when using multiple databases/i) do
        @connection.remove_index_in_background(:users, :name, name: "index_users_on_name")
      end
    end

    private
      def index_valid?(index_name)
        @connection.select_value(<<~SQL)
          SELECT indisvalid
          FROM pg_index i
          JOIN pg_class c
            ON i.indexrelid = c.oid
          WHERE c.relname = #{@connection.quote(index_name)}
        SQL
      end
  end
end
