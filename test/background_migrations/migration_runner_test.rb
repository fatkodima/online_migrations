# frozen_string_literal: true

require "test_helper"

module BackgroundMigrations
  class MigrationRunnerTest < MiniTest::Test
    class User < ActiveRecord::Base
    end

    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users) do |t|
        t.boolean :admin
      end
      User.reset_column_information
      FailingBatch.process_batch_called = 0
      FailingBatch.fail_counter = 2
    end

    def teardown
      @connection.drop_table(:users) rescue nil
      OnlineMigrations::BackgroundMigrations::Migration.delete_all
    end

    def test_run_migration_job_marks_migration_as_running
      2.times { User.create! }
      m = create_migration(batch_size: 1, sub_batch_size: 1)

      run_migration_job(m)
      assert m.running?
    end

    def test_run_migration_job_creates_and_runs_new_job
      3.times { User.create! }
      m = create_migration(batch_size: 3, sub_batch_size: 1)

      assert_equal 0, m.migration_jobs.count
      run_migration_job(m)
      assert_equal 1, m.migration_jobs.count

      job = m.last_job
      assert job.succeeded?
      assert_equal User.first.id, job.min_value
      assert_equal User.last.id, job.max_value
      assert_no_admins
    end

    def test_run_migration_job_edge_batch_range
      _user1, _user2, user3, user4 = 4.times.map { User.create! }
      m = create_migration(max_value: user3.id, batch_size: 2, sub_batch_size: 2)

      run_migration_job(m)
      job = run_migration_job(m)
      assert job.succeeded?
      assert_equal user3.id, job.min_value
      assert_equal user3.id, job.max_value
      assert_equal [user4], User.where(admin: nil)

      # should not create new jobs
      run_migration_job(m)
      assert_equal 2, m.migration_jobs.count
    end

    def test_run_migration_job_retries_jobs
      user1 = User.create!
      _user2 = User.create!
      m = create_migration(batch_size: 1, sub_batch_size: 1)
      failed_job = m.migration_jobs.create!(status: :failed, min_value: user1.id, max_value: user1.id)

      # creates new (and last) job
      run_migration_job(m)

      # retries failed job
      run_migration_job(m)

      assert failed_job.reload.succeeded?
      assert_no_admins
    end

    def test_run_migration_job_finish_with_all_succeeded_jobs
      _user = User.create!
      m = create_migration
      run_migration_job(m)

      # nothing to run, just updates the status
      run_migration_job(m)
      assert m.succeeded?
    end

    def test_run_migration_job_finish_with_failed_jobs
      user = User.create!
      m = create_migration(batch_max_attempts: 2)
      m.migration_jobs.create!(status: :failed, attempts: m.batch_max_attempts, min_value: user.id, max_value: user.id)

      run_migration_job(m)
      assert m.failed?
    end

    def test_run_migration_job_only_running_jobs_left
      user = User.create!
      m = create_migration
      m.migration_jobs.create!(status: :running, min_value: user.id, max_value: user.id)

      run_migration_job(m)
      assert m.running?
    end

    def test_active_support_migration_instrumentation
      _user = User.create!
      m = create_migration(batch_size: 1, sub_batch_size: 1)

      start_called = false
      ActiveSupport::Notifications.subscribe("started.background_migrations") do |*, payload|
        start_called = true
        assert_equal m, payload[:background_migration]
      end

      complete_called = false
      ActiveSupport::Notifications.subscribe("completed.background_migrations") do |*, payload|
        complete_called = true
        assert_equal m, payload[:background_migration]
      end

      run_migration_job(m)
      assert start_called
      assert_not complete_called

      run_migration_job(m)
      assert complete_called
    ensure
      ActiveSupport::Notifications.unsubscribe("started.background_migrations")
      ActiveSupport::Notifications.unsubscribe("completed.background_migrations")
    end

    def test_throttling
      previous = OnlineMigrations.config.background_migrations.throttler

      throttler_called = 0
      OnlineMigrations.config.background_migrations.throttler = -> do
        throttler_called += 1
        throttler_called == 1
      end

      _user = User.create!
      m = create_migration

      throttled_called = 0
      ActiveSupport::Notifications.subscribe("throttled.background_migrations") do |*, payload|
        throttled_called += 1
        assert_equal m, payload[:background_migration]
      end

      # Throttled
      run_migration_job(m)
      assert_equal 1, throttled_called
      assert_equal 0, m.migration_jobs.count

      run_migration_job(m)
      assert_equal 1, throttled_called
      assert_equal 1, m.migration_jobs.count
    ensure
      OnlineMigrations.config.background_migrations.throttler = previous
    end

    def test_run_all_migration_jobs
      4.times { User.create! }
      m = create_migration(batch_size: 2, sub_batch_size: 2)

      run_all_migration_jobs(m)

      assert_no_admins
    end

    def test_run_all_migration_jobs_in_production_like_environment
      User.create!
      m = create_migration

      Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
        error = assert_raises(RuntimeError) do
          run_all_migration_jobs(m)
        end
        assert_equal "This method is not intended for use in production environments", error.message
      end
    end

    def test_finish
      4.times { User.create! }
      m = create_migration(batch_size: 2, sub_batch_size: 2)

      # this does half of the work
      run_migration_job(m)

      runner = migration_runner(m)
      runner.finish

      assert m.succeeded?
      assert_no_admins
    end

    private
      def create_migration(attributes = {})
        OnlineMigrations::BackgroundMigrations::Migration.create!(
          { migration_name: "MakeAllNonAdmins" }.merge(attributes)
        )
      end

      def run_migration_job(migration)
        migration_runner(migration).run_migration_job
      end

      def run_all_migration_jobs(migration)
        migration_runner(migration).run_all_migration_jobs
      end

      def migration_runner(migration)
        OnlineMigrations::BackgroundMigrations::MigrationRunner.new(migration)
      end

      def assert_no_admins
        refute User.exists?(admin: [nil, true])
      end
  end
end
