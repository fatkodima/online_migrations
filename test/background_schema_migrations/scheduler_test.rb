# frozen_string_literal: true

require "test_helper"

module BackgroundSchemaMigrations
  class SchedulerTest < Minitest::Test
    def teardown
      OnlineMigrations::BackgroundSchemaMigrations::Migration.delete_all
      on_each_shard { Dog.connection.remove_index(:dogs, :name) }
    end

    def test_run
      m = create_migration
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

    def test_run_retries_failed_migrations
      m = create_migration
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

    private
      def create_migration
        ActiveRecord::Base.connection.create_background_schema_migration(
          "index_dogs_on_name",
          "dogs",
          definition: 'CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS "index_dogs_on_name" ON "dogs" ("name")',
          connection_class_name: "ShardRecord"
        )
      end
  end
end
