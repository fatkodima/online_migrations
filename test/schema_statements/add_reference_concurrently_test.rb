# frozen_string_literal: true

require "test_helper"

module SchemaStatements
  class AddReferenceConcurrentlyTest < Minitest::Test
    class Milestone < ActiveRecord::Base
    end

    attr_reader :connection

    def setup
      @connection = ActiveRecord::Base.connection

      @connection.create_table(:projects, force: :cascade)
      @connection.create_table(:milestones, force: true)
    end

    def teardown
      connection.drop_table(:milestones, if_exists: true)
      connection.drop_table(:projects, if_exists: true)
    end

    def test_add_reference_concurrently_in_transaction
      assert_raises_in_transaction do
        connection.add_reference_concurrently :milestones, :project
      end
    end

    def test_add_reference_concurrently
      connection.add_reference_concurrently :milestones, :project

      Milestone.reset_column_information
      assert_includes Milestone.column_names, "project_id"
    end

    def test_add_reference_concurrently_adds_index
      connection.add_reference_concurrently :milestones, :project
      index = connection.indexes(:milestones).first

      assert_equal "index_milestones_on_project_id", index.name
    end

    def test_add_reference_concurrently_add_index_hash
      connection.add_reference_concurrently :milestones, :project, index: { name: "project_idx" }
      index = connection.indexes(:milestones).first
      assert_equal "project_idx", index.name
    end

    def test_add_reference_concurrently_without_index
      connection.add_reference_concurrently :milestones, :project, index: false
      assert_empty connection.indexes(:milestones)
    end

    def test_add_reference_concurrently_without_foreign_key_by_default
      connection.add_reference_concurrently :milestones, :project
      assert_empty connection.foreign_keys(:milestones)
    end

    def test_add_reference_concurrently_without_foreign_key
      connection.add_reference_concurrently :milestones, :project, foreign_key: false
      assert_empty connection.foreign_keys(:milestones)
    end

    def test_add_reference_concurrently_with_foreign_key
      assert_sql(
        'REFERENCES "projects" ("id") NOT VALID',
        'ALTER TABLE "milestones" VALIDATE CONSTRAINT'
      ) do
        connection.add_reference_concurrently :milestones, :project, foreign_key: true
      end
    end

    def test_add_reference_concurrently_with_foreign_key_is_idempotent
      assert_empty connection.foreign_keys(:milestones)

      connection.add_reference_concurrently :milestones, :project, foreign_key: true
      connection.add_reference_concurrently :milestones, :project, foreign_key: true
      connection.add_reference_concurrently :milestones, :project, foreign_key: true

      assert_equal 1, connection.foreign_keys(:milestones).size
    end

    def test_add_reference_concurrently_with_foreign_key_with_pluralized_table_name
      assert_sql(
        'REFERENCES "projects" ("id") NOT VALID',
        'ALTER TABLE "milestones" VALIDATE CONSTRAINT'
      ) do
        connection.add_reference_concurrently :milestones, :projects, foreign_key: true
      end
    end

    def test_add_reference_concurrently_with_foreign_key_is_idempotent_with_pluralized_table_name
      assert_empty connection.foreign_keys(:milestones)

      connection.add_reference_concurrently :milestones, :projects, foreign_key: true
      connection.add_reference_concurrently :milestones, :projects, foreign_key: true
      connection.add_reference_concurrently :milestones, :projects, foreign_key: true

      assert_equal 1, connection.foreign_keys(:milestones).size
    end

    def test_add_reference_concurrently_with_unvalidated_foreign_key
      refute_sql("VALIDATE CONSTRAINT") do
        connection.add_reference_concurrently :milestones, :project, foreign_key: { validate: false }
      end
    end

    def test_add_reference_concurrently_when_already_references_target_table_via_foreign_key
      assert_empty connection.foreign_keys(:milestones)

      connection.add_reference_concurrently :milestones, :project, foreign_key: true
      connection.add_reference_concurrently :milestones, :root_project, foreign_key: { to_table: :projects }

      assert_equal 2, connection.foreign_keys(:milestones).size
    end
  end
end
