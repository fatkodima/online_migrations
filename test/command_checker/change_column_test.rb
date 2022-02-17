# frozen_string_literal: true

require "test_helper"

module CommandChecker
  class ChangeColumnTest < MiniTest::Test
    attr_reader :connection

    def setup
      @connection = ActiveRecord::Base.connection

      @connection.create_table :files, force: true do |t|
        t.string :name, limit: 20
        t.text :name_text
        t.decimal :size, precision: 10, scale: 4
        t.decimal :cost_per_gb, null: true
        t.timestamp :created_at
      end
    end

    def teardown
      connection.drop_table(:files) rescue nil
    end

    class ChangeColumnType < TestMigration
      def up
        change_column :files, :cost_per_gb, :integer
      end

      def down; end
    end

    def test_change_column_type
      assert_unsafe ChangeColumnType, <<-MSG.strip_heredoc
        Changing the type of an existing column blocks reads and writes while the entire table is rewritten.
        A safer approach can be accomplished in several steps:

        1. Create a new column and keep column's data in sync:

          class InitializeCommandChecker::ChangeColumnTest::ChangeColumnType < #{migration_parent_string}
            def change
              initialize_column_type_change :files, :cost_per_gb, :integer
            end
          end

        2. Backfill data from the old column to the new column:

          class BackfillCommandChecker::ChangeColumnTest::ChangeColumnType < #{migration_parent_string}
            disable_ddl_transaction!

            def up
              backfill_column_for_type_change :files, :cost_per_gb
            end

            def down
              # no op
            end
          end

        3. Copy indexes, foreign keys, check constraints, NOT NULL constraint, swap new column in place:

          class FinalizeCommandChecker::ChangeColumnTest::ChangeColumnType < #{migration_parent_string}
            disable_ddl_transaction!

            def change
              finalize_column_type_change :files, :cost_per_gb
            end
          end

        4. Deploy
        5. Finally, if everything is working as expected, remove copy trigger and old column:

          class CleanupCommandChecker::ChangeColumnTest::ChangeColumnType < #{migration_parent_string}
            def up
              cleanup_change_column_type_concurrently :files, :cost_per_gb
            end

            def down
              initialize_column_type_change :files, :cost_per_gb, :decimal
            end
          end

        6. Deploy
      MSG
    end

    class IncreaseStringLimit < TestMigration
      def up
        change_column :files, :name, :string, limit: 50
      end

      def down; end
    end

    def test_increase_string_limit
      assert_safe IncreaseStringLimit
    end

    class DecreaseStringLimit < TestMigration
      def up
        change_column :files, :name, :string, limit: 10
      end

      def down; end
    end

    def test_decrease_string_limit
      assert_unsafe DecreaseStringLimit
    end

    class RemoveStringLimit < TestMigration
      def up
        change_column :files, :name, :string
      end

      def down; end
    end

    def test_remove_string_limit
      assert_safe RemoveStringLimit
    end

    class ChangeStringToText < TestMigration
      def up
        change_column :files, :name, :text
      end

      def down; end
    end

    def test_change_string_to_text
      assert_safe ChangeStringToText
    end

    class ChangeTextToUnlimitedString < TestMigration
      def up
        change_column :files, :name_text, :string
      end

      def down; end
    end

    def test_change_text_to_unlimited_string
      assert_safe ChangeTextToUnlimitedString
    end

    class ChangeTextToLimitedString < TestMigration
      def up
        change_column :files, :name_text, :string, limit: 20
      end

      def down; end
    end

    def test_change_text_to_limited_string
      assert_unsafe ChangeTextToLimitedString
    end

    class ChangeTextToText < TestMigration
      def up
        change_column :files, :name_text, :text, default: "New file"
      end

      def down; end
    end

    def test_change_text_to_text
      assert_safe ChangeTextToText
    end

    class MakeDecimalUnconstrained < TestMigration
      def up
        change_column :files, :size, :decimal
      end

      def down; end
    end

    def test_make_numeric_unconstrained
      assert_safe MakeDecimalUnconstrained
    end

    class IncreasePrecisionSameScale < TestMigration
      def up
        change_column :files, :size, :decimal, precision: 15, scale: 4
      end

      def down; end
    end

    def test_increase_precision_same_scale
      assert_safe IncreasePrecisionSameScale
    end

    class IncreasePrecisionDifferentScale < TestMigration
      def up
        change_column :files, :size, :decimal, precision: 15, scale: 10
      end

      def down; end
    end

    def test_increase_precision_different_scale
      assert_unsafe IncreasePrecisionDifferentScale
    end

    class TimestampToTimestamptz < TestMigration
      def up
        change_column :files, :created_at, :timestamptz
      end

      def down; end
    end

    def test_timestamp_to_timestamptz_no_utc
      assert_unsafe TimestampToTimestamptz
    end

    def test_timestamp_to_timestamptz_utc
      with_postgres(12) do
        with_utc_time_zone do
          assert_safe TimestampToTimestamptz
        end
      end
    end

    def test_timestamp_to_timestamptz_utc_before_12
      with_postgres(11) do
        with_utc_time_zone do
          assert_unsafe TimestampToTimestamptz
        end
      end
    end

    class TextToCitext < TestMigration
      def up
        add_column :files, :key, :text
        change_column :files, :key, :citext
      end

      def down
        remove_column :files, :key
      end
    end

    def test_text_to_citext
      assert_safe TextToCitext
    end

    class TextToCitextIndexed < TestMigration
      def up
        change_table :files do |t|
          t.text :key, index: true
        end
        change_column :files, :key, :citext
      end

      def down
        remove_column :files, :key
      end
    end

    def test_text_to_citext_indexed
      assert_unsafe TextToCitextIndexed
    end

    class TextToCitextExpressionIndexed < TestMigration
      def up
        change_table :files do |t|
          t.text :key
          t.index "lower(key)"
        end
        change_column :files, :key, :citext
      end

      def down
        remove_column :files, :key
      end
    end

    def test_text_to_citext_expression_indexed
      assert_unsafe TextToCitextExpressionIndexed
    end

    class CitextToText < TestMigration
      def up
        add_column :files, :key, :citext
        change_column :files, :key, :text
      end

      def down
        remove_column :files, :key
      end
    end

    def test_citext_to_text
      assert_safe CitextToText
    end

    class CitextToTextIndexed < TestMigration
      def up
        change_table :files do |t|
          t.citext :key, index: true
        end
        change_column :files, :key, :text
      end

      def down
        remove_column :files, :key
      end
    end

    def test_citext_to_text_indexed
      assert_unsafe CitextToTextIndexed
    end

    class StringToCitext < TestMigration
      def up
        change_column :files, :name, :citext
      end

      def down
        change_column :files, :name, :string
      end
    end

    def test_string_to_citext
      assert_safe StringToCitext
    end

    class StringToCitextIndexed < TestMigration
      def up
        safety_assured { add_index(:files, :name) }
        change_column :files, :name, :citext
      end

      def down
        remove_index :files, :name
        change_column :files, :name, :string
      end
    end

    def test_string_to_citext_indexed
      assert_unsafe StringToCitextIndexed
    end

    class AddNotNull < TestMigration
      def up
        change_column :files, :cost_per_gb, :decimal, null: false
      end

      def down; end
    end

    def test_add_not_null
      assert_unsafe AddNotNull, <<-MSG.strip_heredoc
        Changing the type is safe, but setting NOT NULL is not.
      MSG
    end

    class ChangeColumnNewTable < TestMigration
      def up
        create_table :files_new do |t|
          t.integer :cost_per_gb
        end

        change_column :files_new, :cost_per_gb, :decimal
      end

      def down
        drop_table :files_new
      end
    end

    def test_change_column_new_table
      assert_safe ChangeColumnNewTable
    end

    private
      def with_utc_time_zone
        previous = connection.select_value("SHOW TIME ZONE")
        connection.select_value("SET TIME ZONE 'UTC'")
      ensure
        connection.select_value("SET TIME ZONE #{connection.quote(previous)}")
      end
  end
end
