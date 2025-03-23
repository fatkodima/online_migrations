# frozen_string_literal: true

require "test_helper"

module BackgroundSchemaMigrations
  class MigrationTest < Minitest::Test
    class User < ActiveRecord::Base
    end

    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users, force: true) do |t|
        t.string :email
      end
    end

    def teardown
      @connection.drop_table(:users, if_exists: true)
      on_each_shard { Dog.connection.remove_index(:dogs, :name) }
      OnlineMigrations::BackgroundSchemaMigrations::Migration.delete_all
    end

    def test_table_name_length_validation
      max_identifier_length = 63

      m = build_migration(table_name: "users")
      assert m.valid?

      m = build_migration(table_name: "a" * (max_identifier_length + 1))
      assert_not m.valid?
      assert_includes m.errors.full_messages, "Table name is too long (maximum is 63 characters)"
    end

    def test_table_existense_validation
      m = build_migration(table_name: "not_exists")
      assert_not m.valid?
      assert_includes m.errors.full_messages, "Table name 'not_exists' does not exist"
    end

    def test_table_connection_class_check
      m = build_migration(connection_class_name: User.name)
      assert m.valid?

      assert_raises_with_message(StandardError, "connection_class_name is not an ActiveRecord::Base child class") do
        build_migration(connection_class_name: "Array")
      end
    end

    def test_name_validation
      create_migration
      m = build_migration
      assert_not m.valid?
      assert_includes m.errors.full_messages, "Migration name (index_users_on_email) has already been taken. " \
                                              "Consider enqueuing index creation with a different index name via a `:name` option."
    end

    def test_status_transitions
      m = create_migration

      m.status = :succeeded
      assert_not m.valid?
      assert_includes m.errors.full_messages, "Status cannot transition background schema migration from status enqueued to succeeded"

      m.status = :running
      assert m.valid?
    end

    def test_sets_defaults
      config = OnlineMigrations.config.background_schema_migrations

      config.stub(:max_attempts, 10) do
        config.stub(:statement_timeout, 20) do
          m = create_migration

          assert_equal 10, m.max_attempts
          assert_equal 20, m.statement_timeout
          assert m.enqueued?
        end
      end
    end

    def test_retry
      m = create_migration(definition: "SOME INVALID SQL", max_attempts: 1)
      assert_raises(ActiveRecord::StatementInvalid) do
        run_migration(m)
      end

      assert m.failed?

      assert m.retry

      m.reload
      assert m.enqueued?
      assert_equal 0, m.attempts
      assert_nil m.started_at
      assert_nil m.finished_at
      assert_nil m.error_class
      assert_nil m.error_message
      assert_nil m.backtrace
    end

    private
      def create_migration(**attributes)
        m = build_migration(**attributes)
        m.save!
        m
      end

      def build_migration(
        name: "index_users_on_email",
        table_name: "users",
        definition: 'CREATE UNIQUE INDEX CONCURRENTLY "index_users_on_email" ON "users" ("email")',
        **attributes
      )
        OnlineMigrations::BackgroundSchemaMigrations::Migration.new(
          name: name,
          table_name: table_name,
          definition: definition,
          **attributes
        )
      end

      def run_migration(migration)
        runner = OnlineMigrations::BackgroundSchemaMigrations::MigrationRunner.new(migration)
        runner.run
      end
  end
end
