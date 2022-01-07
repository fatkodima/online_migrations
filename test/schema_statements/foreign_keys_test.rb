# frozen_string_literal: true

require "test_helper"

module SchemaStatements
  class ForeignKeysTest < MiniTest::Test
    attr_reader :connection

    def setup
      @connection = ActiveRecord::Base.connection

      @connection.create_table(:projects, force: :cascade)

      @connection.create_table(:milestones, force: true) do |t|
        t.bigint :owner_id
        t.bigint :project_id
      end
    end

    def teardown
      connection.drop_table(:milestones) rescue nil
      connection.drop_table(:projects) rescue nil
    end

    def test_add_foreign_key
      connection.add_foreign_key :milestones, :projects
      assert connection.foreign_key_exists?(:milestones, :projects)
    end

    def test_add_foreign_key_when_exists
      connection.add_foreign_key :milestones, :projects
      connection.add_foreign_key :milestones, :projects # once again
      assert connection.foreign_key_exists?(:milestones, :projects)
    end

    def test_validate_foreign_key
      connection.add_foreign_key :milestones, :projects, validate: false
      assert_sql("ALTER TABLE milestones VALIDATE CONSTRAINT") do
        connection.validate_foreign_key :milestones, :projects
      end
    end

    def test_validate_non_existing_foreign_key
      error = assert_raises(ArgumentError) do
        connection.validate_foreign_key :milestones, :non_existing
      end
      assert_match("has no foreign key", error.message)
    end
  end
end
