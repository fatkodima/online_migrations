# frozen_string_literal: true

require "test_helper"

module BackgroundDataMigrations
  class MigrationTest < Minitest::Test
    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users, force: true) do |t|
        t.string :name
        t.boolean :admin
      end

      User.reset_column_information
    end

    def teardown
      @connection.drop_table(:users, if_exists: true)
      OnlineMigrations::BackgroundDataMigrations::Migration.delete_all
    end

    def test_status_transitions
      m = create_migration

      m.status = :succeeded
      assert_not m.valid?
      assert_includes m.errors.full_messages, "Status cannot transition data migration from status 'enqueued' to 'succeeded'"

      m.status = :running
      assert m.valid?
    end

    def test_sets_defaults
      m = create_migration

      assert m.enqueued?

      config = OnlineMigrations.config.background_data_migrations
      assert_equal config.max_attempts, m.max_attempts
      assert_equal config.iteration_pause, m.iteration_pause
    end

    def test_normalizes_migration_name
      m = build_migration(migration_name: "::BackgroundDataMigrations::MakeAllNonAdmins")
      assert_equal "MakeAllNonAdmins", m.migration_name
    end

    def test_progress_succeded_migration
      m = build_migration(status: :succeeded)
      assert_in_delta 100.0, m.progress
    end

    def test_progress_enqueued_migration
      m = build_migration(status: :enqueued)
      assert_in_delta 0.0, m.progress
    end

    def test_progress_not_finished_migration
      2.times { User.create! }
      m = create_migration(migration_name: "MigrationWithCount")

      m.update!(status: :running, tick_count: 1)
      assert_in_delta 50.0, m.progress

      m.update!(tick_count: 2)
      assert_in_delta 100.0, m.progress
    end

    def test_progress_running_migration_without_records
      assert_equal 0, EmptyCollection.new.count
      m = create_migration(migration_name: "EmptyCollection")
      assert_in_delta 0.0, m.progress
    end

    def test_data_migration
      m = build_migration
      assert_instance_of MakeAllNonAdmins, m.data_migration
    end

    def test_retry
      m = create_migration
      m.update_column(:status, :succeeded)
      assert_equal false, m.retry

      m.update_columns(status: :failed, error_class: "NameError")
      assert m.retry

      m.reload
      assert_nil m.started_at
      assert_nil m.finished_at
      assert_nil m.error_class
      assert m.enqueued?
    end

    private
      def create_migration(**attributes)
        m = build_migration(**attributes)
        m.save!
        m
      end

      def build_migration(migration_name: "MakeAllNonAdmins", **attributes)
        OnlineMigrations::BackgroundDataMigrations::Migration.new(migration_name: migration_name, **attributes)
      end

      def run_iteration(migration)
        migration.start if !migration.running?
        data_migration = migration.data_migration
        data_migration.process(data_migration.collection.first)
      end
  end
end
