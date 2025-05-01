# frozen_string_literal: true

require "test_helper"

module BackgroundDataMigrations
  class CopyColumnTest < Minitest::Test
    class Project < ActiveRecord::Base
      default_scope { where(archived: false) }
    end

    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:projects, id: :serial, force: :cascade) do |t|
        t.string :name
        t.text :settings
        t.boolean :archived
        t.bigint :id_for_type_change
        t.jsonb :settings_for_type_change
      end

      Project.reset_column_information

      @project1 = Project.create!(name: "rails", settings: '{"key":"value"}')
      @project2 = Project.create!(name: "postgresql")
    end

    def teardown
      @connection.drop_table(:projects, if_exists: true)
    end

    def test_collection
      m = OnlineMigrations::BackgroundDataMigrations::CopyColumn.new(:projects, ["id"], ["id_for_type_change"])
      assert_kind_of ActiveRecord::Batches::BatchEnumerator, m.collection
    end

    def test_collection_considers_all_rows
      Project.update_all(id_for_type_change: 0) # is typically set via initialize_column_type_change

      m = OnlineMigrations::BackgroundDataMigrations::CopyColumn.new(:projects, ["id"], ["id_for_type_change"])
      run_migration(m)

      @project1.reload
      @project2.reload

      assert_equal @project1.id, @project1.id_for_type_change
      assert_equal @project2.id, @project2.id_for_type_change
    end

    def test_process
      m = OnlineMigrations::BackgroundDataMigrations::CopyColumn.new(:projects, ["id"], ["id_for_type_change"], Project.name)
      run_migration(m)

      @project1.reload
      @project2.reload

      assert_equal @project1.id, @project1.id_for_type_change
      assert_equal @project2.id, @project2.id_for_type_change
    end

    def test_process_with_type_cast_function
      m = OnlineMigrations::BackgroundDataMigrations::CopyColumn.new(:projects, ["settings"], ["settings_for_type_change"], nil, { "settings" => "jsonb" })
      run_migration(m)

      @project1.reload
      assert_equal "value", @project1.settings_for_type_change["key"]
    end

    def test_process_with_type_cast_expression
      m = OnlineMigrations::BackgroundDataMigrations::CopyColumn.new(:projects, ["settings"], ["settings_for_type_change"], nil, { "settings" => "CAST(settings AS jsonb)" })
      run_migration(m)

      @project1.reload
      assert_equal "value", @project1.settings_for_type_change["key"]
    end

    def test_count
      m = OnlineMigrations::BackgroundDataMigrations::CopyColumn.new(:projects, ["id"], ["id_for_type_change"])
      assert_kind_of Integer, m.count
    end

    private
      def run_migration(migration)
        migration.collection.each do |relation|
          migration.process(relation)
        end
      end
  end
end
