# frozen_string_literal: true

require "test_helper"

module BackgroundSchemaMigrations
  class MigrationRunnerTest < Minitest::Test
    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users) do |t|
        t.string :email
      end

      @connection.create_table(:projects) do |t|
        t.integer :user_id
      end

      User.reset_column_information
      Project.reset_column_information
    end

    def teardown
      @connection.drop_table(:projects, if_exists: true)
      @connection.drop_table(:users, if_exists: true)

      on_each_shard do
        Dog.connection.remove_index(:dogs, :name)
        Dog.delete_all
      end

      OnlineMigrations::BackgroundSchemaMigrations::Migration.delete_all
    end

    def test_run_runs_migration
      m = create_migration
      assert m.pending?

      run_migration(m)

      assert m.succeeded?
      assert_equal 1, m.attempts
      assert m.started_at
      assert m.finished_at
      assert_nil m.error_class
      assert_nil m.error_message
      assert_nil m.backtrace
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
      assert_not index.valid?

      User.delete_all # we can now create a unique index

      m = create_migration
      run_migration(m)
      assert m.reload.succeeded?

      index = @connection.indexes(:users).find { |i| i.name == "index_users_on_email" }
      assert index
      assert index.valid?
    end

    def test_adding_existing_index
      @connection.add_index(:users, :email, unique: true)
      m = create_migration
      run_migration(m)
      assert m.reload.succeeded?
    end

    def test_validating_foreign_key
      @connection.add_foreign_key(:projects, :users, validate: false)
      @connection.validate_foreign_key_in_background(:projects, :users, connection_class_name: "Project")
      m = last_schema_migration
      run_migration(m)
      assert m.reload.succeeded?
      foreign_key = @connection.foreign_keys(:projects).first
      assert foreign_key.validated?
    end

    def test_run_saves_error_when_errored
      m = create_migration(definition: "SOME INVALID SQL")
      assert_raises(ActiveRecord::StatementInvalid) do
        run_migration(m)
      end

      assert m.errored?
      assert m.finished_at
      assert_equal "ActiveRecord::StatementInvalid", m.error_class
      assert_match(/PG::SyntaxError/, m.error_message)
      assert_not m.backtrace.empty?
    end

    def test_run_calls_error_handler_when_errored
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
        assert_equal m, payload[:migration]
      end

      run_called = false
      ActiveSupport::Notifications.subscribe("run.background_schema_migrations") do |*, payload|
        run_called = true
        assert_equal m, payload[:migration]
      end

      complete_called = false
      ActiveSupport::Notifications.subscribe("completed.background_schema_migrations") do |*, payload|
        complete_called = true
        assert_equal m, payload[:migration]
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
        assert_equal m, payload[:migration]
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
        OnlineMigrations.config.stub(:run_background_migrations_inline, -> { false }) do
          @connection.enqueue_background_schema_migration(
            name,
            table_name,
            definition: definition,
            connection_class_name: "ActiveRecord::Base",
            **attributes
          )
        end

        last_schema_migration
      end

      def run_migration(migration)
        runner = OnlineMigrations::BackgroundSchemaMigrations::MigrationRunner.new(migration)
        runner.run
      end
  end
end
