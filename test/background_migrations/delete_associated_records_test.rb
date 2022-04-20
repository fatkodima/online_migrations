# frozen_string_literal: true

require "test_helper"

module BackgroundMigrations
  class DeleteAssociatedRecordTest < MiniTest::Test
    class Link < ActiveRecord::Base
      has_many :clicks
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
      @connection.drop_table(:links) rescue nil
      @connection.drop_table(:clicks) rescue nil
    end

    def test_relation
      migration = OnlineMigrations::BackgroundMigrations::DeleteAssociatedRecords.new(Link.name, @link1.id, :clicks)

      assert_kind_of ActiveRecord::Relation, migration.relation
      assert_equal [@click1.id, @click3.id], migration.relation.pluck(:id).sort
    end

    def test_process_batch
      migration = OnlineMigrations::BackgroundMigrations::DeleteAssociatedRecords.new(Link.name, @link1.id, :clicks)
      migration.process_batch(migration.relation)

      assert_not  Click.exists?(@click1.id)
      assert      Click.exists?(@click2.id)
      assert_not  Click.exists?(@click3.id)
    end

    def test_raises_for_unknown_association
      migration = OnlineMigrations::BackgroundMigrations::DeleteAssociatedRecords.new(Link.name, @link1.id, :non_existent)

      assert_raises_with_message(ArgumentError, "'#{Link.name}' has no association called 'non_existent'") do
        migration.process_batch(migration.relation)
      end
    end

    def test_count
      migration = OnlineMigrations::BackgroundMigrations::DeleteAssociatedRecords.new(Link.name, @link1.id, :clicks)
      assert_equal :no_count, migration.count
    end
  end
end
