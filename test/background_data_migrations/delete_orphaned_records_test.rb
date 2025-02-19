# frozen_string_literal: true

require "test_helper"

module BackgroundDataMigrations
  class DeleteOrphanedRecordsTest < Minitest::Test
    class User < ActiveRecord::Base
      has_many :posts
      has_many :comments
    end

    class Post < ActiveRecord::Base
      default_scope { where(archived: false) }

      belongs_to :author, class_name: User.name, optional: true
      has_many :comments
    end

    class Comment < ActiveRecord::Base
      belongs_to :post
    end

    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users, force: :cascade)

      @connection.create_table(:posts, force: :cascade) do |t|
        t.boolean :archived, default: false
        t.belongs_to :author
      end

      @connection.create_table(:comments, force: :cascade) do |t|
        t.belongs_to :post
      end

      User.reset_column_information
      Post.reset_column_information
      Comment.reset_column_information

      user = User.create!

      @post1 = Post.create!
      @post2 = Post.create!(archived: true)
      @post3 = Post.create!(author: user)
    end

    def teardown
      @connection.drop_table(:users, if_exists: true)
      @connection.drop_table(:posts, if_exists: true)
      @connection.drop_table(:comments, if_exists: true)
    end

    def test_collection
      migration = OnlineMigrations::BackgroundDataMigrations::DeleteOrphanedRecords.new(Post.name, [:author])

      assert_kind_of ActiveRecord::Relation, migration.collection
      assert_equal [@post1.id, @post2.id], migration.collection.pluck(:id).sort
    end

    def test_process
      migration = OnlineMigrations::BackgroundDataMigrations::DeleteOrphanedRecords.new(Post.name, [:author])
      migration.collection.each do |record|
        migration.process(record)
      end

      assert_not Post.exists?(@post1.id)
      assert_not Post.exists?(@post2.id)
      assert Post.exists?(@post3.id)
    end

    def test_multiple_associations
      @post1.comments.create!

      migration = OnlineMigrations::BackgroundDataMigrations::DeleteOrphanedRecords.new(Post.name, [:author, :comments])
      migration.collection.each do |record|
        migration.process(record)
      end

      assert Post.exists?(@post1.id)
      assert_not Post.exists?(@post2.id)
      assert Post.exists?(@post3.id)
    end
  end
end
