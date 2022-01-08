# frozen_string_literal: true

require "test_helper"

module BackgroundMigrations
  class SchedulerTest < MiniTest::Test
    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users) do |t|
        t.boolean :admin
      end
    end

    def teardown
      @connection.drop_table(:users) rescue nil
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
  end
end
