# frozen_string_literal: true

require "test_helper"

module BackgroundSchemaMigrations
  class SchedulerTest < Minitest::Test
    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users, force: true) do |t|
        t.string :email
      end
    end

    def teardown
      OnlineMigrations::BackgroundSchemaMigrations::Migration.delete_all
      on_each_shard { Dog.connection.remove_index(:dogs, :name) }
      @connection.drop_table(:users, if_exists: true)
    end

    def test_run
      m = create_migration
      run_scheduler

      assert m.reload.succeeded?
    end

    def test_run_specific_shard
      m = create_migration(
        name: "index_dogs_on_name",
        table_name: "dogs",
        definition: 'CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS "index_dogs_on_name" ON "dogs" ("name")',
        connection_class_name: "ShardRecord"
      )

      run_scheduler(shard: :shard_two)
      assert m.reload.succeeded?
    end

    def test_run_retries_errored_migrations
      m = create_migration

      # Emulate errored migration.
      m.update_column(:status, :errored)

      run_scheduler

      assert m.reload.succeeded?
    end

    def test_run_retries_stuck_migrations
      m = create_migration(statement_timeout: 1.hour)
      m.update(status: :running, updated_at: 2.hours.ago) # emulate stuck migration

      run_scheduler
      assert m.reload.succeeded?
    end

    def test_run_when_on_the_same_table_already_running
      m1 = create_migration
      m1.update_column(:status, :running) # emulate running migration

      _m2 = create_migration(
        definition: 'CREATE INDEX CONCURRENTLY "index_users_on_name" ON "users" ("email")'
      )

      assert_equal [m1], OnlineMigrations::BackgroundSchemaMigrations::Migration.running.to_a
      run_scheduler
      assert_equal [m1], OnlineMigrations::BackgroundSchemaMigrations::Migration.running.to_a
    end

    private
      def create_migration(
        name: "index_users_on_name",
        table_name: "users",
        definition: 'CREATE INDEX CONCURRENTLY "index_users_on_name" ON "users" ("email")',
        **options
      )
        OnlineMigrations.config.stub(:run_background_migrations_inline, -> { false }) do
          @connection.enqueue_background_schema_migration(
            name,
            table_name,
            definition: definition,
            connection_class_name: "ActiveRecord::Base",
            **options
          )
        end

        OnlineMigrations::BackgroundSchemaMigrations::Migration.last
      end

      def run_scheduler(**options)
        scheduler = OnlineMigrations::BackgroundSchemaMigrations::Scheduler.new
        scheduler.run(**options)
      end
  end
end
