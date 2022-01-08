# frozen_string_literal: true

require "test_helper"

module BackgroundMigrations
  class MigrationTest < MiniTest::Test
    class User < ActiveRecord::Base
    end

    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users) do |t|
        t.string :name
        t.boolean :admin
      end

      @connection.create_table(:projects) do |t|
        t.bigint :user_id
      end
    end

    def teardown
      @connection.drop_table(:projects) rescue nil
      @connection.drop_table(:users) rescue nil
      OnlineMigrations::BackgroundMigrations::Migration.delete_all
    end

    def test_min_value_and_max_value_validations
      m = build_migration(min_value: 10, max_value: 1)
      m.valid?

      assert_includes m.errors.full_messages, "max_value should be greater than or equal to min_value"
    end

    def test_batch_size_and_sub_batch_size_validations
      m = build_migration(batch_size: 1000, sub_batch_size: 2000)
      m.valid?

      assert_includes m.errors.full_messages, "sub_batch_size should be smaller than or equal to batch_size"
    end

    def test_sets_defaults
      user1 = User.create!
      user2 = User.create!

      m = create_migration

      assert m.enqueued?
      assert_equal "id", m.batch_column_name
      assert_equal user1.id, m.min_value
      assert_equal user2.id, m.max_value
    end

    def test_normalizes_migration_name
      m = build_migration(migration_name: "::BackgroundMigrations::MakeAllNonAdmins")
      assert_equal "MakeAllNonAdmins", m.migration_name
    end

    def test_empty_relation
      m = create_migration(migration_name: "EmptyRelation")
      assert_equal 1, m.min_value
      assert_equal 1, m.max_value
      assert m.enqueued?
    end

    def test_progress_succeded_migration
      m = create_migration(status: OnlineMigrations::BackgroundMigrations::Migration.statuses[:succeeded])
      assert_equal 1.0, m.progress
    end

    def test_progress_not_finished_migration
      2.times { User.create! }
      m = create_migration(migration_name: "MigrationWithCount", batch_size: 1, sub_batch_size: 1)

      run_migration_job(m)
      assert_equal 0.5, m.progress

      run_migration_job(m)
      assert_equal 1.0, m.progress
    end

    def test_migration_class
      m = build_migration
      assert_equal MakeAllNonAdmins, m.migration_class
    end

    def test_migration_object
      m = build_migration
      assert_instance_of MakeAllNonAdmins, m.migration_object
    end

    def test_migration_relation
      m = build_migration
      assert_kind_of ActiveRecord::Relation, m.migration_relation
    end

    def test_interval_elapsed_p
      _user1 = User.create!
      user2 = User.create!

      m = create_migration(batch_pause: 2.minutes, batch_size: 1, sub_batch_size: 1)

      assert m.interval_elapsed?

      run_migration_job(m)

      Time.stub(:current, 1.minute.from_now) do
        assert_not m.interval_elapsed?
      end

      Time.stub(:current, 3.minutes.from_now) do
        assert m.interval_elapsed?

        _job = m.migration_jobs.create!(min_value: user2.id, max_value: user2.id, status: "running")
        assert_not m.interval_elapsed?
      end
    end

    def test_retry_failed_jobs
      2.times { User.create! }
      m = create_migration(batch_size: 1, sub_batch_size: 1)
      3.times { run_migration_job(m) }
      assert m.succeeded?

      m.update_column(:status, "failed")
      m.migration_jobs.update_all(status: "failed")

      m.retry_failed_jobs
      assert m.migration_jobs.all?(&:enqueued?)
      assert m.enqueued?
    end

    def test_next_batch_range
      user1, user2, user3 = 3.times.map { User.create! }
      m = create_migration(batch_size: 2, sub_batch_size: 1)

      assert_equal [user1.id, user2.id], m.next_batch_range
      run_migration_job(m)
      assert_equal [user3.id, user3.id], m.next_batch_range
      run_migration_job(m)
      assert_nil m.next_batch_range
    end

    def test_next_batch_range_empty_relation
      m = create_migration(migration_name: "EmptyRelation")
      assert_nil m.next_batch_range
    end

    def test_next_batch_range_on_edges
      _user1, _user2, user3, _user4 = 4.times.map { User.create! }
      m = create_migration(max_value: user3.id, batch_size: 2, sub_batch_size: 1)

      run_migration_job(m)
      assert_equal [user3.id, user3.id], m.next_batch_range
    end

    private
      def create_migration(attributes = {})
        migration = build_migration(attributes)
        migration.save!
        migration
      end

      def build_migration(attributes = {})
        OnlineMigrations::BackgroundMigrations::Migration.new(
          { migration_name: "MakeAllNonAdmins" }.merge(attributes)
        )
      end

      def run_migration_job(migration)
        OnlineMigrations::BackgroundMigrations::MigrationRunner.new(migration).run_migration_job
      end
  end
end
