# frozen_string_literal: true

require "test_helper"

module SchemaStatements
  class ForeignKeysTest < Minitest::Test
    attr_reader :connection

    def setup
      @connection = ActiveRecord::Base.connection

      @connection.create_table(:users, force: :cascade)
      @connection.create_table(:projects, force: :cascade)

      @connection.create_table(:milestones, force: true) do |t|
        t.bigint :owner_id
        t.bigint :project_id
        t.bigint :parent_project_id
      end
    end

    def teardown
      connection.drop_table(:milestones, if_exists: true)
      connection.drop_table(:projects, if_exists: true)
      connection.drop_table(:users, if_exists: true)

      OnlineMigrations::BackgroundSchemaMigrations::Migration.delete_all
    end

    def test_add_foreign_key_is_idempotent
      connection.add_foreign_key :milestones, :projects
      connection.add_foreign_key :milestones, :projects # once again
      assert connection.foreign_key_exists?(:milestones, :projects)
    end

    def test_add_foreign_key_referencing_same_table_by_different_columns
      connection.add_foreign_key :milestones, :projects, column: :parent_project_id
      assert_equal 1, connection.foreign_keys(:milestones).size

      connection.add_foreign_key :milestones, :projects
      assert_equal 2, connection.foreign_keys(:milestones).size
    end

    def test_validate_non_existing_foreign_key
      assert_raises_with_message(ArgumentError, "has no foreign key") do
        connection.validate_foreign_key :milestones, :non_existing
      end
    end

    def test_remove_foreign_key
      connection.add_foreign_key :milestones, :projects
      assert connection.foreign_key_exists?(:milestones, :projects)

      connection.remove_foreign_key :milestones, :projects
      assert_not connection.foreign_key_exists?(:milestones, :projects)
    end

    def test_remove_foreign_key_when_not_exists
      assert_empty connection.foreign_keys(:milestones)

      assert_nothing_raised do
        connection.remove_foreign_key :milestones, :projects
      end
    end

    def test_validate_foreign_key_in_background
      connection.add_foreign_key(:milestones, :projects, validate: false)

      m = connection.validate_foreign_key_in_background(:milestones, :projects, connection_class_name: "User")
      assert_equal "fk_rails_9bd0a0c791", m.name
      assert_equal "milestones", m.table_name
      assert_equal 'ALTER TABLE "milestones" VALIDATE CONSTRAINT "fk_rails_9bd0a0c791"', m.definition
    end

    def test_validate_foreign_key_in_background_raises_when_does_not_exist
      assert_raises_with_message(RuntimeError, /the foreign key does not exist/i) do
        # For multiple databases it just warns, but we need a raise.
        OnlineMigrations::Utils.stub(:multiple_databases?, false) do
          connection.validate_foreign_key_in_background(:milestones, :projects, connection_class_name: "User")
        end
      end
    end

    def test_validate_foreign_key_in_background_custom_attributes
      connection.add_foreign_key(:milestones, :projects, name: "my_foreign_key", validate: false)

      m = connection.validate_foreign_key_in_background(
        :milestones, :projects, name: "my_foreign_key",
        max_attempts: 15, connection_class_name: "User"
      )
      assert_equal "my_foreign_key", m.name
      assert_equal 15, m.max_attempts
    end
  end
end
