# frozen_string_literal: true

module OnlineMigrations
  module BackgroundDataMigrations
    # @private
    class BackfillColumn < DataMigration
      attr_reader :table_name, :updates, :model

      def initialize(table_name, updates, model_name = nil)
        @table_name = table_name
        @updates = updates

        @model =
          if model_name
            Object.const_get(model_name, false)
          else
            Utils.define_model(table_name)
          end
      end

      def collection
        column, value = updates.first

        relation =
          if updates.size == 1 && !value.nil?
            # If value is nil, the generated SQL is correct (`WHERE column IS NOT NULL`).
            # Otherwise, the SQL is `WHERE column != value`. This condition ignores column
            # with NULLs in it, so we need to also manually check for NULLs.
            arel_column = model.arel_table[column]
            model.unscoped.where(arel_column.not_eq(value).or(arel_column.eq(nil)))
          else
            model.unscoped.where.not(updates)
          end

        relation.in_batches(of: 100, use_ranges: true)
      end

      def process(relation)
        relation.update_all(updates)
      end

      def count
        # Exact counts are expensive on large tables, since PostgreSQL
        # needs to do a full scan. An estimated count should give a pretty decent
        # approximation of rows count in this case.
        Utils.estimated_count(model.connection, table_name)
      end
    end
  end
end
