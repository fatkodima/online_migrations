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
      end
    end

    def teardown
      connection.drop_table(:milestones, if_exists: true)
      connection.drop_table(:projects, if_exists: true)
      connection.drop_table(:users, if_exists: true)
    end

    def test_add_foreign_key_is_idempotent
      connection.add_foreign_key :milestones, :projects
      connection.add_foreign_key :milestones, :projects # once again
      assert connection.foreign_key_exists?(:milestones, :projects)
    end

    def test_validate_foreign_key_disables_statement_timeout
      connection.add_foreign_key :milestones, :projects, validate: false
      assert_sql("SET statement_timeout TO 0") do
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
