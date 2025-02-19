# frozen_string_literal: true

require "test_helper"

module BackgroundDataMigrations
  class DeleteAssociatedRecordsTest < Minitest::Test
    class Link < ActiveRecord::Base
      has_many :clicks, dependent: :delete_all
    end

    class Click < ActiveRecord::Base
      belongs_to :link
    end

    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:links, force: :cascade)

      @connection.create_table(:clicks, force: :cascade) do |t|
        t.belongs_to :link
      end

      Link.reset_column_information
      Click.reset_column_information

      @link1 = Link.create!
      @link2 = Link.create!

      @click1 = @link1.clicks.create!
      @click2 = @link2.clicks.create!
      @click3 = @link1.clicks.create!
    end

    def teardown
      @connection.drop_table(:links, if_exists: true)
      @connection.drop_table(:clicks, if_exists: true)
    end

    def test_collection
      migration = OnlineMigrations::BackgroundDataMigrations::DeleteAssociatedRecords.new(Link.name, @link1.id, :clicks)

      assert_kind_of ActiveRecord::Batches::BatchEnumerator, migration.collection
      assert_equal [@click1.id, @click3.id], migration.collection.flat_map(&:ids).sort
    end

    def test_process
      migration = OnlineMigrations::BackgroundDataMigrations::DeleteAssociatedRecords.new(Link.name, @link1.id, :clicks)
      migration.process(migration.collection.relation)

      assert_not  Click.exists?(@click1.id)
      assert      Click.exists?(@click2.id)
      assert_not  Click.exists?(@click3.id)
    end

    def test_raises_for_unknown_association
      migration = OnlineMigrations::BackgroundDataMigrations::DeleteAssociatedRecords.new(Link.name, @link1.id, :non_existent)

      assert_raises_with_message(ArgumentError, "'#{Link.name}' has no association called 'non_existent'") do
        migration.process_batch(migration.collection.relation)
      end
    end

    def test_count
      migration = OnlineMigrations::BackgroundDataMigrations::DeleteAssociatedRecords.new(Link.name, @link1.id, :clicks)
      assert_equal 2, migration.count
    end
  end
end
