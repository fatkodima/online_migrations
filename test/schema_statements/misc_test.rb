# frozen_string_literal: true

require "test_helper"

module SchemaStatements
  class MiscTest < MiniTest::Test
    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users, force: :cascade) do |t|
        t.text :name
        t.string :name_for_type_change
      end
    end

    def teardown
      @connection.drop_table(:users) rescue nil
    end

    def test_swap_column_names
      @connection.swap_column_names(:users, :name, :name_for_type_change)

      assert_equal :string, column_for(:users, :name).type
      assert_equal :text, column_for(:users, :name_for_type_change).type
    end

    private
      def column_for(table_name, column_name)
        @connection.columns(table_name).find { |c| c.name == column_name.to_s }
      end
  end
end
