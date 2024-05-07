# frozen_string_literal: true

require "test_helper"

module BackgroundSchemaMigrations
  class MigrationRunnerTest < Minitest::Test
    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users) do |t|
        t.string :email
      end

      User.reset_column_information
    end

    def teardown
      @connection.drop_table(:users, if_exists: true)
      on_each_shard { Dog.connection.remove_index(:dogs, :name) }
      OnlineMigrations::BackgroundSchemaMigrations::Migration.delete_all
    end

    def test_run_marks_migration_and_its_parent_as_running
      m = create_sharded_migration
      child = m.children.first
      assert m.enqueued?
      assert child.enqueued?

      run_migration(child)
      assert child.reload.succeeded?
      assert child.started_at
      assert child.finished_at

      assert m.reload.running?
      assert m.started_at
      assert_nil m.finished_at
    end

    def test_run_runs_migration
      m = create_migration
      run_migration(m)

      assert m.succeeded?
      assert_equal 1, m.attempts
      assert m.started_at
      assert m.finished_at
      assert_nil m.error_class
      assert_nil m.error_message
      assert_nil m.backtrace
    end

    def test_run_runs_sharded_migration_and_its_children
      m = create_sharded_migration
      run_migration(m)
      assert m.reload.succeeded?
      assert m.children.all?(&:succeeded?)
    end

    def test_run_child_migration_completes_parent_if_needed
      m = create_sharded_migration
      child1, child2, child3 = m.children.to_a

      run_migration(child1)
      run_migration(child2)
      assert child1.succeeded?
      assert child2.succeeded?
      assert child3.enqueued?
      assert m.reload.running?

      run_migration(child3)
      assert child3.succeeded?
      assert m.reload.succeeded?
    end

    def test_recreates_invalid_indexes
      # create duplicate users
      2.times do
        User.create!(email: "user@example.com")
      end

      # create invalid index
      assert_raises(ActiveRecord::RecordNotUnique) do
        @connection.add_index(:users, :email, unique: true, algorithm: :concurrently)
      end

      index = @connection.indexes(:users).find { |i| i.name == "index_users_on_email" }
      assert index

      if OnlineMigrations::Utils.ar_version >= 7.1
        assert_not index.valid?
      end

      User.delete_all # we can now create a unique index

      m = create_migration
      run_migration(m)
      assert m.reload.succeeded?

      index = @connection.indexes(:users).find { |i| i.name == "index_users_on_email" }
      assert index

      if OnlineMigrations::Utils.ar_version >= 7.1
        assert index.valid?
      end
    end

    def test_adding_existing_index
      @connection.add_index(:users, :email, unique: true)
      m = create_migration
      run_migration(m)
      assert m.reload.succeeded?
    end

    def test_run_saves_error_when_failed
      m = create_migration(definition: "SOME INVALID SQL")
      assert_raises(ActiveRecord::StatementInvalid) do
        run_migration(m)
      end

      assert m.failed?
      assert m.finished_at
      assert_equal "ActiveRecord::StatementInvalid", m.error_class
      assert_match(/PG::SyntaxError/, m.error_message)
      assert_not m.backtrace.empty?
    end

    def test_run_calls_error_handler_when_failed
      previous = OnlineMigrations.config.background_schema_migrations.error_handler
      m = create_migration(definition: "SOME INVALID SQL")

      handled_error = nil
      OnlineMigrations.config.background_schema_migrations.error_handler = ->(error, errored_migration) do
        handled_error = error
        assert_equal m, errored_migration
      end

      assert_raises(ActiveRecord::StatementInvalid) do
        run_migration(m)
      end

      assert_instance_of ActiveRecord::StatementInvalid, handled_error
    ensure
      OnlineMigrations.config.background_schema_migrations.error_handler = previous
    end

    def test_run_reraises_error_when_running_background_migrations_inline
      m = create_migration(definition: "SOME INVALID SQL")

      prev = OnlineMigrations.config.run_background_migrations_inline
      OnlineMigrations.config.run_background_migrations_inline = -> { true }

      assert_raises(ActiveRecord::StatementInvalid) do
        run_migration(m)
      end
    ensure
      OnlineMigrations.config.run_background_migrations_inline = prev
    end

    def test_run_do_not_reraise_error_when_running_background_migrations_in_background
      m = create_migration(definition: "SOME INVALID SQL")

      OnlineMigrations.config.stub(:run_background_migrations_inline, nil) do
        assert_nothing_raised do
          run_migration(m)
        end
      end
    end

    def test_uses_custom_statement_timeout
      m = create_migration(statement_timeout: 42)
      assert_sql("SET statement_timeout TO 42000") do
        run_migration(m)
      end
    end

    def test_active_support_instrumentation
      m = create_migration

      start_called = false
      ActiveSupport::Notifications.subscribe("started.background_schema_migrations") do |*, payload|
        start_called = true
        assert_equal m, payload[:background_schema_migration]
      end

      run_called = false
      ActiveSupport::Notifications.subscribe("run.background_schema_migrations") do |*, payload|
        run_called = true
        assert_equal m, payload[:background_schema_migration]
      end

      complete_called = false
      ActiveSupport::Notifications.subscribe("completed.background_schema_migrations") do |*, payload|
        complete_called = true
        assert_equal m, payload[:background_schema_migration]
      end

      run_migration(m)
      assert start_called
      assert run_called
      assert complete_called
    ensure
      ActiveSupport::Notifications.unsubscribe("started.background_schema_migrations")
      ActiveSupport::Notifications.unsubscribe("run.background_schema_migrations")
      ActiveSupport::Notifications.unsubscribe("completed.background_schema_migrations")
    end

    def test_throttling
      previous = OnlineMigrations.config.throttler

      throttler_called = 0
      OnlineMigrations.config.throttler = -> do
        throttler_called += 1
        throttler_called == 1
      end

      m = create_migration

      throttled_called = 0
      ActiveSupport::Notifications.subscribe("throttled.background_schema_migrations") do |*, payload|
        throttled_called += 1
        assert_equal m, payload[:background_schema_migration]
      end

      # Throttled
      run_migration(m)
      assert_equal 1, throttled_called
      assert m.running?

      run_migration(m)
      assert_equal 1, throttled_called
      assert m.succeeded?
    ensure
      OnlineMigrations.config.throttler = previous
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
          definition: 'CREATE INDEX CONCURRENTLY "index_dogs_on_name" ON "dogs" ("name")',
          connection_class_name: "ShardRecord"
        )
      end

      def run_migration(migration)
        runner = OnlineMigrations::BackgroundSchemaMigrations::MigrationRunner.new(migration)
        runner.run
      end
  end
end
