# frozen_string_literal: true

require "test_helper"

module SchemaStatements
  class ForeignKeysTest < MiniTest::Test
    attr_reader :connection

    def setup
      @connection = ActiveRecord::Base.connection

      @connection.create_table(:users, force: :cascade)
      @connection.create_table(:projects, force: :cascade)

      @connection.create_table(:milestones, force: true) do |t|
        t.bigint :owner_id
        t.bigint :project_id
      end
    end

    def teardown
      connection.drop_table(:milestones) rescue nil
      connection.drop_table(:projects) rescue nil
      connection.drop_table(:users) rescue nil
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

    def test_add_unvalidated_foreign_key
      assert_sql("NOT VALID") do
        connection.add_foreign_key :milestones, :projects, validate: false
      end
    end

    def test_add_foreign_key_custom_name
      connection.add_foreign_key :milestones, :projects, name: "custom_fk_name"

      fkey = connection.foreign_keys(:milestones).first
      assert_equal "custom_fk_name", fkey.name
    end

    def test_add_foreign_key_default_column
      connection.add_foreign_key :milestones, :projects

      fkey = connection.foreign_keys(:milestones).first
      assert_equal "project_id", fkey.column
    end

    def test_add_foreign_key_custom_column
      connection.add_foreign_key :milestones, :users, column: :owner_id

      fkey = connection.foreign_keys(:milestones).first
      assert_equal "owner_id", fkey.column
    end

    def test_add_foreign_key_custom_on_delete
      connection.add_foreign_key :milestones, :projects, on_delete: :cascade

      fkey = connection.foreign_keys(:milestones).first
      assert_equal :cascade, fkey.on_delete
    end

    def test_add_foreign_key_on_delete_nil
      connection.add_foreign_key :milestones, :projects, on_delete: nil

      fkey = connection.foreign_keys(:milestones).first
      assert_nil fkey.on_delete
    end

    def test_add_foreign_key_custom_on_update
      connection.add_foreign_key :milestones, :projects, on_update: :cascade

      fkey = connection.foreign_keys(:milestones).first
      assert_equal :cascade, fkey.on_update
    end

    def test_add_foreign_key_on_update_nil
      connection.add_foreign_key :milestones, :projects, on_update: nil

      fkey = connection.foreign_keys(:milestones).first
      assert_nil fkey.on_update
    end

    def test_add_foreign_key_raises_on_invalid_actions
      assert_raises(ArgumentError) do
        connection.add_foreign_key :milestones, :projects, on_delete: :invalid
      end

      assert_raises(ArgumentError) do
        connection.add_foreign_key :milestones, :projects, on_update: :invalid
      end
    end

    def test_validate_foreign_key
      connection.add_foreign_key :milestones, :projects, validate: false
      assert_sql("ALTER TABLE milestones VALIDATE CONSTRAINT") do
        connection.validate_foreign_key :milestones, :projects
      end
    end

    def test_validate_non_existing_foreign_key
      assert_raises_with_message(ArgumentError, "has no foreign key") do
        connection.validate_foreign_key :milestones, :non_existing
      end
    end
  end
end
