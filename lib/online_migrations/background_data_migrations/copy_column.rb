# frozen_string_literal: true

module OnlineMigrations
  module BackgroundDataMigrations
    # @private
    class CopyColumn < DataMigration
      attr_reader :table_name, :copy_from, :copy_to, :model_name, :type_cast_functions

      def initialize(table_name, copy_from, copy_to, model_name = nil, type_cast_functions = {})
        @table_name = table_name

        if copy_from.is_a?(Array) && type_cast_functions && !type_cast_functions.is_a?(Hash)
          raise ArgumentError, "type_cast_functions must be a Hash"
        end

        @copy_from = Array.wrap(copy_from)
        @copy_to = Array.wrap(copy_to)

        if @copy_from.size != @copy_to.size
          raise ArgumentError, "Number of source and destination columns must match"
        end

        @model_name = model_name
        @model =
          if model_name.present?
            Object.const_get(model_name, false)
          else
            Utils.define_model(table_name)
          end

        @type_cast_functions = type_cast_functions
      end

      def collection
        @model.unscoped.in_batches(of: 100, use_ranges: true)
      end

      def process(relation)
        arel_table = relation.arel_table

        old_values = copy_from.map do |from_column|
          old_value = arel_table[from_column]
          if (type_cast_function = type_cast_functions[from_column])
            old_value =
              if type_cast_function.match?(/\A\w+\z/)
                Arel::Nodes::NamedFunction.new(type_cast_function, [old_value])
              else
                # We got a cast expression.
                Arel.sql(type_cast_function)
              end
          end
          old_value
        end

        updates = copy_to.zip(old_values).to_h { |to_column, old_value| [to_column, old_value] }
        relation.update_all(updates)
      end

      def count
        # Exact counts are expensive on large tables, since PostgreSQL
        # needs to do a full scan. An estimated count should give a pretty decent
        # approximation of rows count in this case.
        Utils.estimated_count(@model.connection, table_name)
      end
    end
  end
end
