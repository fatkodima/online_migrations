# frozen_string_literal: true

module OnlineMigrations
  module BackgroundMigrations
    # @private
    class BackfillColumn < BackgroundMigration
      attr_reader :table_name, :updates, :model_name

      def initialize(table_name, updates, model_name = nil)
        @table_name = table_name
        @updates = updates
        @model_name = model_name
      end

      def relation
        column, value = updates.first

        if updates.size == 1 && !value.nil?
          # If value is nil, the generated SQL is correct (`WHERE column IS NOT NULL`).
          # Otherwise, the SQL is `WHERE column != value`. This condition ignores column
          # with NULLs in it, so we need to also manually check for NULLs.
          quoted_column = connection.quote_column_name(column)
          model.where("#{quoted_column} != ? OR #{quoted_column} IS NULL", value)
        else
          Utils.ar_where_not_multiple_conditions(model, updates)
        end
      end

      def process_batch(relation)
        relation.update_all(updates)
      end

      def count
        # Exact counts are expensive on large tables, since PostgreSQL
        # needs to do a full scan. An estimated count should give a pretty decent
        # approximation of rows count in this case.
        Utils.estimated_count(connection, table_name)
      end

      private
        def model
          @model ||= if model_name.present?
                       Object.const_get(model_name, false)
                     else
                       Utils.define_model(ActiveRecord::Base.connection, table_name)
                     end
        end

        def connection
          model.connection
        end
    end
  end
end
