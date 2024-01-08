# frozen_string_literal: true

require "test_helper"

module BackgroundMigrations
  class SchedulerTest < Minitest::Test
    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users) do |t|
        t.boolean :admin
      end

      User.reset_column_information
    end

    def teardown
      @connection.drop_table(:users, if_exists: true)
      OnlineMigrations::BackgroundMigrations::Migration.delete_all
    end

    def test_run
      user1 = User.create!
      user2 = User.create!
      user3 = User.create!

      m = OnlineMigrations::BackgroundMigrations::Migration.create!(
        migration_name: "MakeAllNonAdmins",
        batch_size: 2,
        sub_batch_size: 1,
        batch_pause: 2.minutes
      )

      scheduler = OnlineMigrations::BackgroundMigrations::Scheduler.new
      scheduler.run

      assert m.reload.running?
      assert_equal false, user1.reload.admin
      assert_equal false, user2.reload.admin
      assert_nil user3.reload.admin

      # interval has not elapsed
      scheduler.run
      assert_nil user3.reload.admin

      # interval elapsed
      Time.stub(:current, 5.minutes.from_now) do
        scheduler.run
        assert_equal false, user3.reload.admin
      end
    end

    def test_run_migration_has_stuck_job
      user1 = User.create!
      user2 = User.create!

      m = OnlineMigrations::BackgroundMigrations::Migration.create!(
        migration_name: "MakeAllNonAdmins",
        batch_size: 1,
        sub_batch_size: 1
      )

      scheduler = OnlineMigrations::BackgroundMigrations::Scheduler.new
      scheduler.run

      assert m.reload.running?

      # Emulate stuck migration job.
      user1.update_column(:admin, nil)
      job = m.migration_jobs.first
      job.update_columns(status: :running, updated_at: 2.minutes.ago)

      OnlineMigrations.config.background_migrations.stub(:stuck_jobs_timeout, 1.minute) do
        scheduler.run
        assert_nil user1.reload.admin
        assert_equal false, user2.reload.admin

        scheduler.run # stuck job should run
        assert_equal false, user2.reload.admin
      end

      scheduler.run # last run to ensure there are no more work
      assert m.reload.completed?
    end
  end
end
