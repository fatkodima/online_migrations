# frozen_string_literal: true

require "test_helper"

module BackgroundMigrations
  class ResetCountersTest < MiniTest::Test
    class User < ActiveRecord::Base
      default_scope { where(banned: false) }

      has_many :projects
    end

    class Project < ActiveRecord::Base
      belongs_to :user, counter_cache: true
      has_many :subscriptions
      has_many :subscribers, through: :subscriptions
    end

    class Subscription < ActiveRecord::Base
      belongs_to :project, counter_cache: :subscribers_count
      belongs_to :subscriber, class_name: User.name
    end

    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users, force: :cascade) do |t|
        t.boolean :banned, default: false
        t.integer :projects_count
        t.timestamp :touched_at
        t.timestamps(null: false)
      end

      @connection.create_table(:projects, force: :cascade) do |t|
        t.belongs_to :user
        t.integer :subscribers_count
      end

      @connection.create_table(:subscriptions, force: :cascade) do |t|
        t.belongs_to :project
        t.belongs_to :subscriber
      end

      User.reset_column_information
      Project.reset_column_information
      Subscription.reset_column_information

      @user1 = User.create!(banned: true)
      @user2 = User.create!
      @user3 = User.create!

      @project1 = @user1.projects.create!
      @project2 = @user1.projects.create!
      @project3 = @user3.projects.create!

      # Reset manually counters, generated via counter cache
      User.unscoped.update_all(projects_count: 0)
    end

    def teardown
      @connection.drop_table(:users) rescue nil
      @connection.drop_table(:projects) rescue nil
      @connection.drop_table(:subscriptions) rescue nil
    end

    def test_relation
      migration = OnlineMigrations::BackgroundMigrations::ResetCounters.new(User.name, [:projects])

      assert_kind_of ActiveRecord::Relation, migration.relation
      assert_equal [@user1.id, @user2.id, @user3.id], migration.relation.pluck(:id).sort
    end

    def test_process_batch
      migration = OnlineMigrations::BackgroundMigrations::ResetCounters.new(User.name, [:projects])
      migration.process_batch(migration.relation)

      assert_equal 2, @user1.reload.projects_count
      assert_equal 0, @user2.reload.projects_count
      assert_equal 1, @user3.reload.projects_count
    end

    def test_raises_for_unknown_association
      migration = OnlineMigrations::BackgroundMigrations::ResetCounters.new(User.name, [:non_existent])

      error = assert_raises(ArgumentError) do
        migration.process_batch(migration.relation)
      end
      assert_equal "'#{User.name}' has no association called 'non_existent'", error.message
    end

    def test_counter_as_column_name
      migration = OnlineMigrations::BackgroundMigrations::ResetCounters.new(User.name, [:projects_count])
      migration.process_batch(migration.relation)

      assert_equal 2, @user1.reload.projects_count
      assert_equal 0, @user2.reload.projects_count
      assert_equal 1, @user3.reload.projects_count
    end

    def test_has_many_through_association
      @project1.subscriptions.create!(subscriber: @user2)
      @project1.subscriptions.create!(subscriber: @user3)
      @project3.subscriptions.create!(subscriber: @user1)

      # Reset manually counters, generated via counter cache
      Project.unscoped.update_all(subscribers_count: 0)

      migration = OnlineMigrations::BackgroundMigrations::ResetCounters.new(Project.name, [:subscribers])
      migration.process_batch(migration.relation)

      assert_equal 2, @project1.reload.subscribers_count
      assert_equal 0, @project2.reload.subscribers_count
      assert_equal 1, @project3.reload.subscribers_count
    end

    def test_touches_parent
      prev_updated_at = 3.days.ago
      @user1.update!(updated_at: prev_updated_at)

      migration = OnlineMigrations::BackgroundMigrations::ResetCounters.new(User.name, [:projects], { touch: true })
      migration.process_batch(migration.relation)

      refute_equal prev_updated_at, @user1.reload.updated_at
    end

    def test_touches_specific_parent_column
      prev_timestamp = 3.days.ago
      @user1.update!(updated_at: prev_timestamp, touched_at: prev_timestamp)

      migration = OnlineMigrations::BackgroundMigrations::ResetCounters.new(User.name, [:projects], { touch: :touched_at })
      migration.process_batch(migration.relation)

      @user1.reload

      refute_equal prev_timestamp, @user1.updated_at
      refute_equal prev_timestamp, @user1.touched_at
    end

    def test_touches_with_concrete_time
      time = 1.day.ago
      migration = OnlineMigrations::BackgroundMigrations::ResetCounters.new(User.name, [:projects], { touch: [time: time] })
      migration.process_batch(migration.relation)

      @user1.reload

      # For ActiveRecord 4.2 need to call to_i for correct comparison
      assert_equal time.to_i, @user1.updated_at.to_i
    end

    def test_count
      migration = OnlineMigrations::BackgroundMigrations::ResetCounters.new(User.name, [:projects])
      assert_kind_of Integer, migration.count
    end
  end
end
