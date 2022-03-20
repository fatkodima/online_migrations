# frozen_string_literal: true

require "test_helper"

module BackgroundMigrations
  class DeleteOrphanedRecordTest < MiniTest::Test
    class User < ActiveRecord::Base
      has_many :posts
      has_many :comments
    end

    class Post < ActiveRecord::Base
      default_scope { where(archived: false) }

      optional_setting = OnlineMigrations::Utils.ar_version > 4.2 ? { optional: true } : { required: false }

      belongs_to :author, class_name: User.name, **optional_setting
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
      Project.reset_column_information
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
      skip if ar_version <= 4.2

      migration = OnlineMigrations::BackgroundMigrations::DeleteOrphanedRecords.new(Post.name, [:author])

      assert_kind_of ActiveRecord::Relation, migration.relation
      assert_equal [@post1.id, @post2.id], migration.relation.pluck(:id).sort
    end

    def test_process_batch
      skip if ar_version <= 4.2

      migration = OnlineMigrations::BackgroundMigrations::DeleteOrphanedRecords.new(Post.name, [:author])
      migration.process_batch(migration.relation)

      assert_not Post.exists?(@post1.id)
      assert_not Post.exists?(@post2.id)
      assert Post.exists?(@post3.id)
    end

    def test_raises_for_unknown_association
      migration = OnlineMigrations::BackgroundMigrations::DeleteOrphanedRecords.new(Post.name, [:non_existent])

      error = assert_raises(ArgumentError) do
        migration.process_batch(migration.relation)
      end
      assert_equal "'#{Post.name}' has no association called 'non_existent'", error.message
    end

    def test_multiple_associations
      skip if ar_version <= 4.2

      @post1.comments.create!

      migration = OnlineMigrations::BackgroundMigrations::DeleteOrphanedRecords.new(Post.name, [:author, :comments])
      migration.process_batch(migration.relation)

      assert Post.exists?(@post1.id)
      assert_not Post.exists?(@post2.id)
      assert Post.exists?(@post3.id)
    end

    def test_count
      skip if ar_version <= 4.2

      migration = OnlineMigrations::BackgroundMigrations::DeleteOrphanedRecords.new(Post.name, [:author])
      assert_kind_of Integer, migration.count
    end
  end
end
