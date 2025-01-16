# frozen_string_literal: true

require "test_helper"

module BackgroundSchemaMigrations
  class SchedulerTest < Minitest::Test
    def teardown
      OnlineMigrations::BackgroundSchemaMigrations::Migration.delete_all
      on_each_shard { Dog.connection.remove_index(:dogs, :name) }
    end

    def test_run
      m = create_migration(
        name: "index_dogs_on_name",
        table_name: "dogs",
        definition: 'CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS "index_dogs_on_name" ON "dogs" ("name")',
        connection_class_name: "ShardRecord"
      )
      child1, child2, child3 = m.children.to_a

      scheduler = OnlineMigrations::BackgroundSchemaMigrations::Scheduler.new
      scheduler.run

      assert m.reload.running?
      assert child1.reload.succeeded?

      scheduler.run
      assert child2.reload.succeeded?

      scheduler.run
      assert child3.reload.succeeded?
      assert m.reload.succeeded?
    end

    def test_run_specific_shard
      m = create_migration(
        name: "index_dogs_on_name",
        table_name: "dogs",
        definition: 'CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS "index_dogs_on_name" ON "dogs" ("name")',
        connection_class_name: "ShardRecord"
      )

      scheduler = OnlineMigrations::BackgroundSchemaMigrations::Scheduler.new
      scheduler.run(shard: :shard_two)

      assert m.reload.running?

      shard_one_migration = m.children.find_by(shard: :shard_one)
      assert shard_one_migration.enqueued?

      shard_two_migration = m.children.find_by(shard: :shard_two)
      assert shard_two_migration.succeeded?
    end

    def test_run_retries_failed_migrations
      m = create_migration(
        name: "index_dogs_on_name",
        table_name: "dogs",
        definition: 'CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS "index_dogs_on_name" ON "dogs" ("name")',
        connection_class_name: "ShardRecord"
      )
      child = m.children.first

      scheduler = OnlineMigrations::BackgroundSchemaMigrations::Scheduler.new
      scheduler.run

      # Emulate failed migration.
      child.update_columns(status: :failed, attempts: child.max_attempts - 1)

      assert m.reload.running?
      assert child.reload.failed?

      3.times { scheduler.run } # 2 children + 1 retry

      assert m.reload.succeeded?
      assert m.children.all?(&:succeeded?)
    end

    def test_run_retries_stuck_migrations
      connection = ActiveRecord::Base.connection
      connection.create_table(:users, force: true) do |t|
        t.string :email
      end

      m = create_migration(
        name: "index_users_on_email",
        table_name: "users",
        definition: 'CREATE UNIQUE INDEX CONCURRENTLY "index_users_on_email" ON "users" ("email")',
        statement_timeout: 1.hour
      )
      m.update(status: :running, updated_at: 2.hours.ago) # emulate stuck migration

      assert_equal 1, OnlineMigrations::BackgroundSchemaMigrations::Migration.running.count

      scheduler = OnlineMigrations::BackgroundSchemaMigrations::Scheduler.new
      scheduler.run

      assert m.reload.succeeded?
    ensure
      connection.drop_table(:users)
    end

    def test_run_when_on_the_same_table_already_running
      connection = ActiveRecord::Base.connection
      connection.create_table(:users, force: true) do |t|
        t.string :email
      end

      m1 = create_migration(
        name: "index_users_on_email",
        table_name: "users",
        definition: 'CREATE UNIQUE INDEX CONCURRENTLY "index_users_on_email" ON "users" ("email")'
      )
      m1.update_column(:status, :running) # emulate running migration

      _m2 = create_migration(
        name: "index_users_on_name",
        table_name: "users",
        definition: 'CREATE INDEX CONCURRENTLY "index_users_on_name" ON "users" ("name")'
      )

      assert_equal 1, OnlineMigrations::BackgroundSchemaMigrations::Migration.running.count

      scheduler = OnlineMigrations::BackgroundSchemaMigrations::Scheduler.new
      scheduler.run

      assert_equal 1, OnlineMigrations::BackgroundSchemaMigrations::Migration.running.count
    ensure
      connection.drop_table(:users)
    end

    private
      def create_migration(name:, table_name:, **options)
        ActiveRecord::Base.connection.create_background_schema_migration(name, table_name, **options)
      end
  end
end
