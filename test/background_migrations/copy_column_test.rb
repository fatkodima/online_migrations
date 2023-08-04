# frozen_string_literal: true

require "test_helper"

module BackgroundMigrations
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
      @connection.drop_table(:projects) rescue nil
    end

    def test_relation
      m = OnlineMigrations::BackgroundMigrations::CopyColumn.new(:projects, ["id"], ["id_for_type_change"])
      assert_kind_of ActiveRecord::Relation, m.relation
    end

    def test_process_batch
      m = OnlineMigrations::BackgroundMigrations::CopyColumn.new(:projects, ["id"], ["id_for_type_change"], Project.name)
      m.process_batch(m.relation)

      @project1.reload
      @project2.reload

      assert_equal @project1.id, @project1.id_for_type_change
      assert_equal @project2.id, @project2.id_for_type_change
    end

    def test_process_batch_type_cast_function
      m = OnlineMigrations::BackgroundMigrations::CopyColumn.new(:projects, ["settings"], ["settings_for_type_change"], nil, { "settings" => "jsonb" })
      m.process_batch(m.relation)

      @project1.reload
      assert_equal "value", @project1.settings_for_type_change["key"]
    end

    def test_count
      m = OnlineMigrations::BackgroundMigrations::CopyColumn.new(:projects, ["id"], ["id_for_type_change"])
      assert_kind_of Integer, m.count
    end
  end
end
