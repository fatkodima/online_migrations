# frozen_string_literal: true

require "test_helper"

module BackgroundMigrations
  class PerformActionOnRelationTest < Minitest::Test
    class User < ActiveRecord::Base
      default_scope { where(banned: [nil, false]) }

      class << self
        attr_accessor :callback_called, :action_called
      end
      self.callback_called = 0
      self.action_called = 0

      before_destroy { self.class.callback_called += 1 }

      def custom_action
        self.class.action_called += 1
      end
    end

    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users, force: :cascade) do |t|
        t.string :email
        t.boolean :banned
      end

      User.reset_column_information
      User.callback_called = 0

      @user1 = User.create!(banned: nil)
      @user2 = User.create!(banned: true)
      @user3 = User.create!(banned: nil, email: "user3@example.com")
    end

    def teardown
      @connection.drop_table(:users) rescue nil
    end

    def test_relation_hash_condition
      migration = OnlineMigrations::BackgroundMigrations::PerformActionOnRelation.new(User.name, { email: nil }, :delete_all)

      assert_kind_of ActiveRecord::Relation, migration.relation
      assert_equal [@user1.id, @user2.id], migration.relation.pluck(:id).sort
    end

    def test_relation_array_condition
      migration = OnlineMigrations::BackgroundMigrations::PerformActionOnRelation.new(User.name, ["banned = ?", true], :delete_all)

      assert_kind_of ActiveRecord::Relation, migration.relation
      assert_equal [@user2.id], migration.relation.pluck(:id)
    end

    def test_relation_string_condition
      migration = OnlineMigrations::BackgroundMigrations::PerformActionOnRelation.new(User.name, "email IS NULL", :delete_all)

      assert_kind_of ActiveRecord::Relation, migration.relation
      assert_equal [@user1.id, @user2.id], migration.relation.pluck(:id).sort
    end

    def test_process_batch_delete_all
      migration = OnlineMigrations::BackgroundMigrations::PerformActionOnRelation.new(User.name, { email: nil }, :delete_all)
      migration.process_batch(migration.relation)

      assert_not  User.exists?(@user1.id)
      assert_not  User.exists?(@user2.id)
      assert      User.exists?(@user3.id)

      assert_equal 0, User.callback_called
    end

    def test_process_batch_destroy_all
      migration = OnlineMigrations::BackgroundMigrations::PerformActionOnRelation.new(User.name, { email: nil }, :destroy_all)
      migration.process_batch(migration.relation)

      assert_not  User.exists?(@user1.id)
      assert_not  User.exists?(@user2.id)
      assert      User.exists?(@user3.id)

      assert_equal 2, User.callback_called
    end

    def test_process_batch_update_all
      assert_nil @user1.banned
      assert     @user2.banned
      assert_nil @user3.banned

      migration = OnlineMigrations::BackgroundMigrations::PerformActionOnRelation.new(User.name,
        { banned: nil }, :update_all, { updates: { banned: false } })
      migration.process_batch(migration.relation)

      assert_equal false, @user1.reload.banned
      assert @user2.reload.banned
      assert_equal false, @user3.reload.banned
    end

    def test_process_batch_custom_action
      migration = OnlineMigrations::BackgroundMigrations::PerformActionOnRelation.new(User.name, { banned: nil }, :custom_action)
      migration.process_batch(migration.relation)

      assert_equal 2, User.action_called
    end

    def test_count
      migration = OnlineMigrations::BackgroundMigrations::PerformActionOnRelation.new(User.name, { email: nil }, :delete_all)
      assert_equal :no_count, migration.count
    end
  end
end
