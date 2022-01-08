# frozen_string_literal: true

require "test_helper"

module BackgroundMigrations
  class MigrationJobTest < MiniTest::Test
    class User < ActiveRecord::Base
    end

    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users) do |t|
        t.boolean :admin
      end
      EachBatchCalled.process_batch_called = 0
    end

    def teardown
      @connection.drop_table(:users) rescue nil
      OnlineMigrations::BackgroundMigrations::Migration.delete_all
    end

    def test_min_value_and_max_value_validations
      m = create_migration(min_value: 1, max_value: 10)
      j = m.migration_jobs.build(min_value: 5, max_value: 1)
      j.valid?

      assert_includes j.errors.full_messages, "max_value should be greater than or equal to min_value"

      j = m.migration_jobs.build(min_value: 1, max_value: 20)
      j.valid?

      assert_includes j.errors.full_messages, "min_value and max_value should be in background migration values range"
    end

    def test_status_transitions
      m = create_migration(min_value: 1, max_value: 10)
      j = m.migration_jobs.create!(min_value: 1, max_value: 10, status: :enqueued)

      j.status = :succeeded
      assert_not j.valid?
      assert_includes j.errors.full_messages, "Status cannot transition background migration job from status enqueued to succeeded"

      j.status = :running
      assert j.valid?
    end

    def test_copies_settings_from_background_migration
      m = create_migration(min_value: 1, max_value: 100, batch_size: 10, sub_batch_size: 5, sub_batch_pause_ms: 20, batch_max_attempts: 2)
      j = m.migration_jobs.create!(min_value: 1, max_value: 10)

      assert_equal m.batch_size, j.batch_size
      assert_equal m.sub_batch_size, j.sub_batch_size
      assert_equal m.sub_batch_pause_ms, j.pause_ms
      assert_equal m.batch_max_attempts, j.max_attempts
    end

    def test_retry
      User.create!
      m = create_migration(migration_name: "EachBatchFails")
      run_migration_job(m)
      j = m.last_job

      j.retry
      assert j.enqueued?
      assert_equal 0, j.attempts
      assert_nil j.started_at
      assert_nil j.finished_at
    end

    private
      def create_migration(attributes = {})
        OnlineMigrations::BackgroundMigrations::Migration.create!(
          { migration_name: "EachBatchCalled" }.merge(attributes)
        )
      end

      def run_migration_job(migration)
        OnlineMigrations::BackgroundMigrations::MigrationRunner.new(migration).run_migration_job
      end
  end
end
