# frozen_string_literal: true

require "test_helper"

module SchemaStatements
  class MiscTest < MiniTest::Test
    class User < ActiveRecord::Base
    end

    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users, force: :cascade) do |t|
        t.text :name
        t.string :status
        t.boolean :admin
        t.bigint :id_for_type_change
        t.string :name_for_type_change
      end
    end

    def teardown
      OnlineMigrations::BackgroundMigrations::Migration.delete_all
      @connection.drop_table(:users) rescue nil
    end

    def test_schema
      if ActiveRecord.version >= Gem::Version.new("7.0.2")
        ActiveRecord::Schema[ar_version].define do
          add_index :users, :name
        end
      else
        ActiveRecord::Schema.define do
          add_index :users, :name
        end
      end
    end

    def test_swap_column_names
      @connection.swap_column_names(:users, :name, :name_for_type_change)

      assert_equal :string, column_for(:users, :name).type
      assert_equal :text, column_for(:users, :name_for_type_change).type
    end

    def test_backfill_column_in_background
      m = @connection.backfill_column_in_background(:users, :admin, false, model_name: User)

      assert_equal "BackfillColumn", m.migration_name
      assert_equal ["users", { "admin" => false }, "SchemaStatements::MiscTest::User"], m.arguments
    end

    def test_backfill_columns_in_background
      m = @connection.backfill_columns_in_background(:users, { admin: false, status: "active" }, model_name: User)

      assert_equal "BackfillColumn", m.migration_name
      assert_equal ["users", { "admin" => false, "status" => "active" }, "SchemaStatements::MiscTest::User"], m.arguments
    end

    def test_copy_column_in_background
      m = @connection.copy_column_in_background(:users, :name, :name_for_type_change, model_name: User)

      assert_equal "CopyColumn", m.migration_name
      assert_equal ["users", ["name"], ["name_for_type_change"], "SchemaStatements::MiscTest::User", { "name" => nil }], m.arguments
    end

    def test_copy_columns_in_background
      m = @connection.copy_columns_in_background(:users, [:id, :name], [:id_for_type_change, :name_for_type_change], model_name: User)

      assert_equal "CopyColumn", m.migration_name
      assert_equal ["users", ["id", "name"], ["id_for_type_change", "name_for_type_change"], "SchemaStatements::MiscTest::User", {}], m.arguments
    end

    def test_enqueue_background_migration
      assert_equal 0, OnlineMigrations::BackgroundMigrations::Migration.count
      @connection.enqueue_background_migration(
        "MakeAllNonAdmins",
        batch_max_attempts: 3,
        sub_batch_pause_ms: 200
      )

      m = OnlineMigrations::BackgroundMigrations::Migration.last
      assert_equal "MakeAllNonAdmins", m.migration_name
      assert_equal 3, m.batch_max_attempts
      assert_equal 200, m.sub_batch_pause_ms
      assert_equal OnlineMigrations.config.background_migrations.batch_size, m.batch_size
    end

    def test_disable_statement_timeout
      prev_value = get_statement_timeout
      set_statement_timeout(10)

      @connection.disable_statement_timeout do
        assert_equal "0", get_statement_timeout
      end
      assert_equal "10ms", get_statement_timeout
    ensure
      set_statement_timeout(prev_value)
    end

    def test_nested_disable_statement_timeouts
      prev_value = get_statement_timeout
      set_statement_timeout(10)

      @connection.disable_statement_timeout do
        set_statement_timeout(20)

        @connection.disable_statement_timeout do
          assert_equal "0", get_statement_timeout
        end

        assert_equal "20ms", get_statement_timeout
      end

      assert_equal "10ms", get_statement_timeout
    ensure
      set_statement_timeout(prev_value)
    end

    private
      def column_for(table_name, column_name)
        @connection.columns(table_name).find { |c| c.name == column_name.to_s }
      end

      def get_statement_timeout
        @connection.select_value("SHOW statement_timeout")
      end

      def set_statement_timeout(value)
        @connection.execute("SET statement_timeout TO #{@connection.quote(value)}")
      end
  end
end
