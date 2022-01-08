# frozen_string_literal: true

require "test_helper"

module BackgroundMigrations
  class MigrationJobRunnerTest < MiniTest::Test
    class User < ActiveRecord::Base
    end

    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users) do |t|
        t.boolean :admin
      end
      FailingBatch.process_batch_called = 0
      FailingBatch.fail_counter = 1
    end

    def teardown
      @connection.drop_table(:users) rescue nil
      OnlineMigrations::BackgroundMigrations::Migration.delete_all
    end

    def test_run_succeeds
      2.times { User.create! }

      job = create_migration_job(migration_name: "MakeAllNonAdmins", batch_size: 2, sub_batch_size: 1)
      run_migration_job(job)

      assert_equal 1, job.attempts
      assert job.succeeded?
      assert job.started_at.present?
      assert job.finished_at.present?

      assert User.count, User.where(admin: false).count
    end

    def test_run_saves_error_when_failed
      _user = User.create!

      job = create_migration_job(migration_name: "EachBatchFails")

      run_migration_job(job)

      assert job.failed?
      assert job.finished_at.present?
      assert_equal "RuntimeError", job.error_class
      assert_equal "Boom!", job.error_message
      assert_not job.backtrace.empty?
    end

    def test_run_calls_error_handler_when_failed
      _user = User.create!
      job = create_migration_job(migration_name: "EachBatchFails")

      previous_error_handler = OnlineMigrations.config.background_migrations.error_handler

      handled_error = nil
      handled_job = nil
      OnlineMigrations.config.background_migrations.error_handler = ->(error, errored_job) do
        handled_error = error
        handled_job = errored_job
      end

      run_migration_job(job)

      assert_equal RuntimeError, handled_error.class
      assert_equal job, handled_job
    ensure
      OnlineMigrations.config.background_migrations.error_handler = previous_error_handler
    end

    def test_active_support_instrumentation
      2.times { User.create! }
      job = create_migration_job(migration_name: "FailingBatch", batch_size: 1, sub_batch_size: 1)

      process_batch_called = 0
      ActiveSupport::Notifications.subscribe("process_batch.background_migrations") do |*, payload|
        process_batch_called += 1
        assert_kind_of OnlineMigrations::BackgroundMigrations::MigrationJob, payload[:background_migration_job]
      end

      retry_called = 0
      ActiveSupport::Notifications.subscribe("retried.background_migrations") do |*, payload|
        retry_called += 1
        assert_kind_of OnlineMigrations::BackgroundMigrations::MigrationJob, payload[:background_migration_job]
      end

      run_migration_job(job)
      assert_equal 0, retry_called
      assert_equal 1, process_batch_called

      # retry failing job
      run_migration_job(job)
      assert_equal 1, retry_called
      assert_equal 2, process_batch_called
    ensure
      ActiveSupport::Notifications.unsubscribe("process_batch.background_migrations")
      ActiveSupport::Notifications.unsubscribe("retried.background_migrations")
    end

    private
      def create_migration_job(migration_attributes)
        m = OnlineMigrations::BackgroundMigrations::Migration.create!(migration_attributes)

        min_value, max_value = m.next_batch_range
        m.migration_jobs.create!(min_value: min_value, max_value: max_value)
      end

      def run_migration_job(migration_job)
        OnlineMigrations::BackgroundMigrations::MigrationJobRunner.new(migration_job).run
      end
  end
end
