# frozen_string_literal: true

require "test_helper"

module BackgroundMigrations
  class CopyColumnTest < MiniTest::Test
    class Project < ActiveRecord::Base
    end

    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:projects, id: :serial, force: :cascade) do |t|
        t.string :name
        t.text :settings
        t.bigint :id_for_type_change
        t.jsonb :settings_for_type_change
      end

      Project.reset_column_information

      @project = Project.create!(name: "rails", settings: '{"key":"value"}')
    end

    def teardown
      @connection.drop_table(:projects) rescue nil
    end

    def test_relation
      m = OnlineMigrations::BackgroundMigrations::CopyColumn.new(:projects, ["id"], ["id_for_type_change"])
      assert_kind_of ActiveRecord::Relation, m.relation
    end

    def test_process_batch
      m = OnlineMigrations::BackgroundMigrations::CopyColumn.new(:projects, ["id"], ["id_for_type_change"])
      m.process_batch(m.relation)

      @project.reload
      assert_equal @project.id, @project.id_for_type_change
    end

    def test_process_batch_type_cast_function
      m = OnlineMigrations::BackgroundMigrations::CopyColumn.new(:projects, ["settings"], ["settings_for_type_change"], nil, { "settings" => "jsonb" })
      m.process_batch(m.relation)

      @project.reload
      assert_equal "value", @project.settings_for_type_change["key"]
    end

    def test_count
      m = OnlineMigrations::BackgroundMigrations::CopyColumn.new(:projects, ["id"], ["id_for_type_change"])
      assert_kind_of Integer, m.count
    end
  end
end
