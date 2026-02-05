# frozen_string_literal: true

require "test_helper"

module BackgroundDataMigrations
  class SchedulerTest < Minitest::Test
    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users, force: :cascade) do |t|
        t.boolean :admin
      end

      User.reset_column_information
    end

    def teardown
      @connection.drop_table(:users, if_exists: true)
      OnlineMigrations::BackgroundDataMigrations::Migration.delete_all
    end

    def test_run
      m = create_migration(migration_name: "MakeAllNonAdmins")

      run_scheduler

      jobs = OnlineMigrations::BackgroundDataMigrations::MigrationJob.jobs
      assert_equal 1, jobs.size
      job = jobs.last
      assert_equal [m.id], job["args"]

      m.reload
      assert m.enqueued?
      assert_not_nil m.jid
    end

    def test_run_specific_shard
      m1 = create_migration(migration_name: "MakeAllDogsNice", shard: :shard_one)
      m2 = create_migration(migration_name: "MakeAllDogsNice", shard: :shard_two)

      run_scheduler(shard: :shard_two)

      jobs = OnlineMigrations::BackgroundDataMigrations::MigrationJob.jobs
      assert_equal 1, jobs.size
      job = jobs.last
      assert_equal [m2.id], job["args"]

      m2.reload
      assert m2.enqueued?
      assert_not_nil m2.jid

      m1.reload
      assert m1.pending?
      assert_nil m1.jid
    end

    def test_run_no_more_than_concurrency
      m1 = create_migration(migration_name: "MakeAllNonAdmins")
      m2 = create_migration(migration_name: "MigrationWithCount")

      scheduler = OnlineMigrations::BackgroundDataMigrations::Scheduler.new
      scheduler.run(concurrency: 1)

      assert_equal 1, OnlineMigrations::BackgroundDataMigrations::MigrationJob.jobs.size
      assert m1.reload.enqueued?
      assert m2.reload.pending?

      run_scheduler(concurrency: 2)

      assert_equal 2, OnlineMigrations::BackgroundDataMigrations::MigrationJob.jobs.size
      assert m1.reload.enqueued?
      assert m2.reload.enqueued?
    end

    def test_stuck_migration_is_rescheduled
      m = create_migration(migration_name: "MakeAllNonAdmins", status: "running", updated_at: 1.hour.ago)

      run_scheduler

      jobs = OnlineMigrations::BackgroundDataMigrations::MigrationJob.jobs
      assert_equal 1, jobs.size
      job = jobs.last
      assert_equal [m.id], job["args"]

      m.reload
      assert m.enqueued?
      assert_not_nil m.jid
    end

    class CustomJob < OnlineMigrations::BackgroundDataMigrations::MigrationJob
    end

    def test_custom_migration_job
      OnlineMigrations.config.background_data_migrations.stub(:job, CustomJob.name) do
        m = create_migration(migration_name: "MakeAllNonAdmins")
        run_scheduler

        assert_equal 1, CustomJob.jobs.size
        assert m.reload.enqueued?
      end
    end

    private
      def create_migration(migration_name:, **attributes)
        OnlineMigrations::BackgroundDataMigrations::Migration.create!(migration_name: migration_name, **attributes)
      end

      def run_scheduler(**options)
        scheduler = OnlineMigrations::BackgroundDataMigrations::Scheduler.new
        scheduler.run(**options)
      end
  end
end
