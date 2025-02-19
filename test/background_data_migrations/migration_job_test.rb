# frozen_string_literal: true

require "test_helper"
require "active_support/testing/constant_stubbing"

module BackgroundDataMigrations
  class MigrationJobTest < Minitest::Test
    include ActiveSupport::Testing::ConstantStubbing

    MigrationJob = OnlineMigrations::BackgroundDataMigrations::MigrationJob

    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users, force: :cascade)

      SimpleDataMigration.descendants.each do |klass|
        klass.processed_objects = []
        klass.after_start_called = 0
        klass.around_process_called = 0
        klass.after_stop_called = 0
        klass.after_complete_called = 0
        klass.after_pause_called = 0
        klass.after_cancel_called = 0
      end
    end

    def teardown
      @connection.drop_table(:users, if_exists: true)
      OnlineMigrations::BackgroundDataMigrations::Migration.delete_all
    end

    def test_raises_when_collection_method_is_missing
      m = create_migration("NoCollectionMigration")
      assert_raises_with_message(NotImplementedError, /must implement a 'collection' method/) do
        MigrationJob.perform_inline(m.id)
      end
    end

    def test_raises_when_process_method_is_missing
      m = create_migration("NoProcessMigration")
      assert_raises_with_message(NotImplementedError, /must implement a 'process' method/) do
        MigrationJob.perform_inline(m.id)
      end
    end

    def test_uses_build_enumerator_method_if_present
      m = create_migration("CustomEnumeratorMigration")
      MigrationJob.perform_inline(m.id)
      assert_equal [1, 2, 3], CustomEnumeratorMigration.processed_objects
    end

    def test_raises_when_build_enumerator_method_returns_non_enumerator
      m = create_migration("NonEnumeratorMigration")
      assert_raises_with_message(ArgumentError, /#build_enumerator must return an Enumerator/) do
        MigrationJob.perform_inline(m.id)
      end
    end

    def test_collection_is_relation
      user1 = User.create!
      user2 = User.create!
      m = create_migration("RelationCollectionMigration")
      MigrationJob.perform_inline(m.id)

      assert_equal [user1, user2], RelationCollectionMigration.processed_objects
    end

    def test_collection_is_batch_enumerator
      user1 = User.create!
      user2 = User.create!
      m = create_migration("BatchesCollectionMigration")
      MigrationJob.perform_inline(m.id)

      relations = BatchesCollectionMigration.processed_objects
      assert relations.all?(ActiveRecord::Relation)
      assert relations.none?(&:loaded?)
      assert_equal [[user1], [user2]], relations.map(&:to_a)
    end

    def test_collection_is_batch_enumerator_with_start
      m = create_migration("BadBatchesCollectionMigration")
      assert_raises_with_message(ArgumentError, /a batch enumerator with the "start" or "finish" options/) do
        MigrationJob.perform_inline(m.id)
      end
    end

    def test_collection_is_array
      m = create_migration("ArrayCollectionMigration")
      MigrationJob.perform_inline(m.id)
      assert_equal [1, 2, 3], ArrayCollectionMigration.processed_objects

      # #count is not set by default.
      assert_nil m.reload.tick_total
    end

    def test_collection_is_not_supported
      m = create_migration("BadCollectionMigration")
      assert_raises_with_message(ArgumentError, /#collection must be either an ActiveRecord::Relation/) do
        MigrationJob.perform_inline(m.id)
      end
    end

    def test_uses_count_method_if_present
      m = create_migration("WithCountMigration")
      MigrationJob.perform_inline(m.id)
      assert_equal 3, m.reload.tick_total
    end

    def test_stores_metadada_about_the_data_migration
      m = create_migration("ArrayCollectionMigration")
      MigrationJob.perform_inline(m.id)

      m.reload
      assert_equal 2, m.cursor.to_i
      assert_not_nil m.started_at
      assert_not_nil m.finished_at
      assert_equal 3, m.tick_count
      assert_not_nil m.time_running
    end

    def test_runs_on_shard
      on_shard(:shard_one) do
        Dog.create!(nice: nil)
      end

      on_shard(:shard_two) do
        Dog.create!(nice: false)
      end

      m = create_migration("MakeAllDogsNice", connection_class_name: "ShardRecord", shard: "shard_one")
      MigrationJob.perform_inline(m.id)

      on_shard(:shard_one) do
        assert Dog.last.nice
      end

      on_shard(:shard_two) do
        assert_not Dog.last.nice
      end
    ensure
      on_each_shard do
        Dog.delete_all
      end
    end

    def test_calls_data_migration_callbacks
      m = create_migration("WithCountMigration")
      MigrationJob.perform_inline(m.id)

      assert_equal 1, ArrayCollectionMigration.after_start_called
      assert_equal 3, ArrayCollectionMigration.around_process_called
      assert_equal 1, ArrayCollectionMigration.after_stop_called
      assert_equal 1, ArrayCollectionMigration.after_complete_called

      m.reload
      assert m.succeeded?
      assert_equal 3, m.tick_total
      assert_equal 3, m.tick_count
      assert_not_nil m.started_at
      assert_not_nil m.finished_at
    end

    def test_stores_current_state
    end

    def test_cancells_cancelling_migration
      m = create_migration("ArrayCollectionMigration")
      m.running! # emulate that the migration was picked up by the scheduler
      m.cancel
      assert m.cancelling?

      MigrationJob.perform_inline(m.id)
      assert_equal 0, ArrayCollectionMigration.after_start_called
      assert_equal 0, ArrayCollectionMigration.around_process_called
      assert_equal 1, ArrayCollectionMigration.after_stop_called
      assert_equal 1, ArrayCollectionMigration.after_complete_called
      assert_equal 0, ArrayCollectionMigration.after_pause_called
      assert_equal 1, ArrayCollectionMigration.after_cancel_called

      m.reload
      assert_nil m.started_at
      assert_not_nil m.finished_at
      assert m.cancelled?
    end

    def test_pauses_pausing_migration
      m = create_migration("ArrayCollectionMigration")
      m.running! # emulate that the migration was picked up by the scheduler
      m.pause
      assert m.pausing?

      MigrationJob.perform_inline(m.id)

      assert_equal 0, ArrayCollectionMigration.after_start_called
      assert_equal 0, ArrayCollectionMigration.around_process_called
      assert_equal 1, ArrayCollectionMigration.after_stop_called
      assert_equal 0, ArrayCollectionMigration.after_complete_called
      assert_equal 1, ArrayCollectionMigration.after_pause_called
      assert_equal 0, ArrayCollectionMigration.after_cancel_called

      m.reload
      assert_nil m.started_at
      assert_nil m.finished_at
      assert m.paused?
    end

    def test_active_support_instrumentation
      m = create_migration("ArrayCollectionMigration")

      start_called = false
      ActiveSupport::Notifications.subscribe("started.background_data_migrations") do |*, payload|
        start_called = true
        assert_equal m, payload[:migration]
      end

      complete_called = false
      ActiveSupport::Notifications.subscribe("completed.background_data_migrations") do |*, payload|
        complete_called = true
        assert_equal m, payload[:migration]
      end

      MigrationJob.perform_inline(m.id)

      assert start_called
      assert complete_called
    ensure
      ActiveSupport::Notifications.unsubscribe("started.background_data_migrations")
      ActiveSupport::Notifications.unsubscribe("completed.background_data_migrations")
    end

    def test_throttling
      previous = OnlineMigrations.config.throttler

      throttler_called = 0
      OnlineMigrations.config.throttler = -> do
        throttler_called += 1
        throttler_called == 2
      end

      m = create_migration("ArrayCollectionMigration")

      throttled_called = 0
      ActiveSupport::Notifications.subscribe("throttled.background_data_migrations") do |*, payload|
        throttled_called += 1
        assert_equal m, payload[:migration]
      end

      # Do not wait before checking if needs to throttle.
      stub_const(MigrationJob, :THROTTLE_CHECK_INTERVAL, 0) do
        MigrationJob.perform_inline(m.id)
      rescue Sidekiq::Job::Interrupted
        # In real world, sidekiq will reenqueue the job.
      end

      assert_equal 1, ArrayCollectionMigration.around_process_called
      assert throttled_called
      assert_equal 1, m.reload.cursor.to_i
    ensure
      OnlineMigrations.config.throttler = previous
    end

    private
      def create_migration(migration_name, **attributes)
        OnlineMigrations::BackgroundDataMigrations::Migration.create!(migration_name: migration_name, **attributes)
      end
  end
end
