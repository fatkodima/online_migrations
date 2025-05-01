# frozen_string_literal: true

require "test_helper"

module BackgroundDataMigrations
  class BackfillColumnTest < Minitest::Test
    class User < ActiveRecord::Base
      default_scope { where(banned: false) }
    end

    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users, force: :cascade) do |t|
        t.boolean :admin
        t.boolean :banned, default: false
      end

      User.reset_column_information

      @user1 = User.create!(admin: nil, banned: true)
      @user2 = User.create!(admin: true)
      @user3 = User.create!(admin: false)
      @migration = OnlineMigrations::BackgroundDataMigrations::BackfillColumn.new(:users, { "admin" => false }, User.name)
    end

    def teardown
      @connection.drop_table(:users, if_exists: true)
    end

    def test_collection
      assert_kind_of ActiveRecord::Batches::BatchEnumerator, @migration.collection
      assert_equal [@user1.id, @user2.id], @migration.collection.flat_map(&:ids).sort
    end

    def test_process
      @migration.collection.each do |relation|
        @migration.process(relation)
      end

      assert_equal false, @user1.reload.admin
      assert_equal false, @user2.reload.admin
      assert_equal false, @user3.reload.admin
    end

    def test_count
      assert_kind_of Integer, @migration.count
    end
  end
end
