# frozen_string_literal: true

require "test_helper"

module BackgroundMigrations
  class BackfillColumnTest < MiniTest::Test
    class User < ActiveRecord::Base
    end

    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users, force: :cascade) do |t|
        t.boolean :admin
      end

      User.reset_column_information

      @user1 = User.create!(admin: nil)
      @user2 = User.create!(admin: true)
      @user3 = User.create!(admin: false)
      @migration = OnlineMigrations::BackgroundMigrations::BackfillColumn.new(:users, { "admin" => false })
    end

    def teardown
      @connection.drop_table(:users) rescue nil
    end

    def test_relation
      assert_kind_of ActiveRecord::Relation, @migration.relation
      assert_equal [@user1.id, @user2.id], @migration.relation.pluck(:id).sort
    end

    def test_process_batch
      @migration.process_batch(@migration.relation)

      assert_equal false, @user1.reload.admin
      assert_equal false, @user2.reload.admin
      assert_equal false, @user3.reload.admin
    end

    def test_count
      assert_kind_of Integer, @migration.count
    end
  end
end
