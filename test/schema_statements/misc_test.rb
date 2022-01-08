# frozen_string_literal: true

require "test_helper"

module SchemaStatements
  class MiscTest < MiniTest::Test
    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users, force: :cascade) do |t|
        t.text :name
        t.string :name_for_type_change
        t.boolean :admin
      end
    end

    def teardown
      OnlineMigrations::BackgroundMigrations::Migration.delete_all
      @connection.drop_table(:users) rescue nil
    end

    def test_swap_column_names
      @connection.swap_column_names(:users, :name, :name_for_type_change)

      assert_equal :string, column_for(:users, :name).type
      assert_equal :text, column_for(:users, :name_for_type_change).type
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

    private
      def column_for(table_name, column_name)
        @connection.columns(table_name).find { |c| c.name == column_name.to_s }
      end
  end
end
