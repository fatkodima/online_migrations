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
      OnlineMigrations::BackgroundSchemaMigrations::Migration.delete_all
      # on_each_shard { Dog.delete_all }
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

    def test_table_connection_class_validation
      m = build_migration(connection_class_name: User.name)
      assert m.valid?

      m = build_migration(connection_class_name: "Array")
      assert_not m.valid?
      assert_includes m.errors.full_messages, "Connection class name is not an ActiveRecord::Base child class"
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
          assert_not m.composite?
          assert_nil m.parent
        end
      end
    end

    def test_progress_succeded_migration
      m = build_migration(status: :succeeded)
      assert_in_delta 100.0, m.progress
    end

    def test_progress_succeded_sharded_migration
      m = build_migration(connection_class_name: "ShardRecord", status: :succeeded)
      assert_in_delta 100.0, m.progress
    end

    def test_progress_failed_migration
      m = build_migration(status: :failed)
      assert_in_delta 0.0, m.progress
    end

    def test_progress_not_finished_sharded_migration
      m = create_sharded_migration

      # child1 is for `:default` and same as child2.
      child1, child2, child3 = m.children.to_a

      run_migration(child1)
      assert_in_delta 100.0 / 3, m.progress, 1

      run_migration(child2)
      run_migration(child3)
      assert_in_delta 100.0, m.progress
    end

    def test_mark_as_succeeded_when_not_all_child_migrations_succeeded
      m = create_sharded_migration
      child1, child2, child3 = m.children.to_a
      run_migration(child1)
      run_migration(child2)

      assert child1.succeeded?
      assert child2.succeeded?
      child3.update_column(:status, :failed) # bypass status validation

      m.reload # so the status is updated

      assert_raises_with_message(ActiveRecord::RecordInvalid, /all child migrations must be succeeded/) do
        m.succeeded!
      end
    end

    def test_mark_as_failed_when_none_of_the_children_migrations_failed
      m = create_sharded_migration
      run_migration(m.children.first)
      assert m.reload.running?

      assert_raises_with_message(ActiveRecord::RecordInvalid, /at least one child migration must be failed/) do
        m.failed!
      end
    end

    def test_creates_child_migrations_for_sharded_migration
      m = create_sharded_migration
      assert m.composite?
      assert_nil m.parent

      children = m.children.order(:shard).to_a
      assert children.none?(&:composite?)

      child1, child2, child3 = children

      assert_equal "default", child1.shard
      assert_equal "shard_one", child2.shard
      assert_equal "shard_two", child3.shard
    end

    def test_retry
      m = create_migration(definition: "SOME INVALID SQL")
      m.max_attempts.times { run_migration(m) }
      assert m.failed?

      m.retry

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
      def create_migration(
        name: "index_users_on_email",
        table_name: "users",
        definition: 'CREATE UNIQUE INDEX CONCURRENTLY "index_users_on_email" ON "users" ("email")',
        **attributes
      )
        @connection.create_background_schema_migration(name, table_name, definition: definition, **attributes)
      end

      def create_sharded_migration
        create_migration(
          name: "index_dogs_on_name",
          table_name: "dogs",
          definition: 'CREATE INDEX CONCURRENTLY IF NOT EXISTS "index_dogs_on_name" ON "dogs" ("name")',
          connection_class_name: "ShardRecord"
        )
      end

      def build_migration(**attributes)
        OnlineMigrations::BackgroundSchemaMigrations::Migration.new(
          {
            name: "index_users_on_email",
            table_name: "users",
            definition: 'CREATE UNIQUE INDEX CONCURRENTLY "index_users_on_email" ON "users" ("email")',
          }.merge(attributes)
        )
      end

      def run_migration(migration)
        runner = OnlineMigrations::BackgroundSchemaMigrations::MigrationRunner.new(migration)
        runner.run
      end
  end
end
