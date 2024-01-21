# frozen_string_literal: true

require "test_helper"

module SchemaStatements
  class UpdateColumnInBatchesTest < Minitest::Test
    class Milestone < ActiveRecord::Base
    end

    attr_reader :connection

    def setup
      @connection = ActiveRecord::Base.connection

      @connection.create_table(:milestones, force: :cascade) do |t|
        t.string :name
        t.integer :points
        t.datetime :started_at
        t.timestamps
      end

      Milestone.reset_column_information
    end

    def teardown
      connection.drop_table(:milestones, if_exists: true)
    end

    def test_update_column_in_batches_raises_in_transaction
      assert_raises_in_transaction do
        connection.update_column_in_batches(:milestones, :name, "No name")
      end
    end

    def test_update_column_in_batches_whole_table
      m1 = Milestone.create!(name: nil)
      m2 = Milestone.create!(name: "Custom name")

      connection.update_column_in_batches(:milestones, :name, "No name")

      assert_equal "No name", m1.reload.name
      assert_equal "No name", m2.reload.name
    end

    def test_update_column_in_batches_custom_condition
      m1 = Milestone.create!(points: nil)
      m2 = Milestone.create!(points: 10)

      connection.update_column_in_batches(:milestones, :points, 0) do |relation|
        relation.where(points: nil)
      end

      assert_equal 0, m1.reload.points
      assert_equal 10, m2.reload.points
    end

    def test_update_column_in_batches_computed_value
      milestone = Milestone.create!(name: "a" * 65, created_at: 2.days.ago, started_at: nil)

      connection.update_column_in_batches(:milestones, :started_at, Arel.sql("created_at"))

      milestone.reload
      assert_equal milestone.created_at, milestone.started_at

      truncated_name = Arel.sql("substring(name from 1 for 64)")
      connection.update_column_in_batches(:milestones, :name, truncated_name)

      milestone.reload
      assert_equal "a" * 64, milestone.name
    end

    def test_update_column_in_batches_expression_value
      m1 = Milestone.create!(started_at: nil)
      m2 = Milestone.create!(started_at: 3.days.ago)

      connection.update_column_in_batches(:milestones, :started_at, -> { "CURRENT_TIMESTAMP" })

      assert_not_nil m1.reload.started_at
      assert m2.reload.started_at > 1.minute.ago # started_at was updated
    end

    def test_update_column_in_batches_value_is_subquery
      Milestone.create!

      refute_sql('"milestones"."points" != (SELECT') do
        connection.update_column_in_batches(:milestones, :points,
          Arel.sql("(SELECT m1.points FROM milestones m1 WHERE m1.id = milestones.id)"))
      end
    end

    def test_update_column_in_batches_configurable_batches
      3.times { Milestone.create! }

      queries = track_queries do
        connection.update_column_in_batches(:milestones, :points, 0, batch_size: 2)
      end

      update_queries = queries.grep(/\AUPDATE "milestones"/)
      assert_equal 2, update_queries.size
    end

    def test_update_column_in_batches_progress
      3.times { Milestone.create! }

      counter = 0
      progress = ->(*) { counter += 1 }
      connection.update_column_in_batches(:milestones, :points, 0, batch_size: 2, progress: progress)

      assert_equal 2, counter
    end

    def test_update_column_in_batches_default_progress_when_enabled
      2.times { Milestone.create! }

      assert_output("..") do
        connection.update_column_in_batches(:milestones, :points, 0, batch_size: 1, progress: true)
      end
    end

    def test_update_column_in_batches_raises_when_non_callable_progress
      assert_raises_with_message(ArgumentError, /needs to be a callable/i) do
        connection.update_column_in_batches(:milestones, :points, 0, progress: :not_callable)
      end
    end

    def test_update_columns_in_batches
      _m1 = Milestone.create!(name: nil, points: nil)
      _m2 = Milestone.create!(name: nil, points: 0)

      connection.update_columns_in_batches(:milestones, [[:name, "Default"], [:points, 0]])
      assert_equal 2, Milestone.where(name: "Default", points: 0).count
    end
  end
end
