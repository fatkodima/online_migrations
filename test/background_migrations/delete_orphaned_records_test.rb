# frozen_string_literal: true

require "test_helper"

module BackgroundMigrations
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
      @connection.drop_table(:users) rescue nil
      @connection.drop_table(:posts) rescue nil
      @connection.drop_table(:comments) rescue nil
    end

    def test_relation
      migration = OnlineMigrations::BackgroundMigrations::DeleteOrphanedRecords.new(Post.name, [:author])

      assert_kind_of ActiveRecord::Relation, migration.relation
      assert_equal [@post1.id, @post2.id], migration.relation.pluck(:id).sort
    end

    def test_process_batch
      migration = OnlineMigrations::BackgroundMigrations::DeleteOrphanedRecords.new(Post.name, [:author])
      migration.process_batch(migration.relation)

      assert_not Post.exists?(@post1.id)
      assert_not Post.exists?(@post2.id)
      assert Post.exists?(@post3.id)
    end

    def test_multiple_associations
      @post1.comments.create!

      migration = OnlineMigrations::BackgroundMigrations::DeleteOrphanedRecords.new(Post.name, [:author, :comments])
      migration.process_batch(migration.relation)

      assert Post.exists?(@post1.id)
      assert_not Post.exists?(@post2.id)
      assert Post.exists?(@post3.id)
    end

    def test_count
      migration = OnlineMigrations::BackgroundMigrations::DeleteOrphanedRecords.new(Post.name, [:author])
      assert_kind_of Integer, migration.count
    end
  end
end
