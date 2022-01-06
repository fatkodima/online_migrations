# frozen_string_literal: true

require "test_helper"

module SchemaStatements
  class IndexesTest < MiniTest::Test
    def setup
      @connection = ActiveRecord::Base.connection

      @connection.create_table(:users, force: true) do |t|
        t.string :name
        t.bigint :company_id
      end
    end

    def teardown
      @connection.drop_table(:users) rescue nil
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

    private
      def index_valid?(index_name)
        @connection.select_value <<~SQL
          SELECT indisvalid
          FROM pg_index i
          JOIN pg_class c
            ON i.indexrelid = c.oid
          WHERE c.relname = #{@connection.quote(index_name)}
        SQL
      end
  end
end
