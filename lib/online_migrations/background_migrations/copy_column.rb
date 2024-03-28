# frozen_string_literal: true

module OnlineMigrations
  module BackgroundMigrations
    # @private
    class CopyColumn < BackgroundMigration
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
        @type_cast_functions = type_cast_functions
      end

      def relation
        model.unscoped
      end

      def process_batch(relation)
        arel = relation.arel
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

        stmt = Arel::UpdateManager.new
        stmt.table(arel_table)
        stmt.wheres = arel.constraints

        updates = copy_to.zip(old_values).map { |to_column, old_value| [arel_table[to_column], old_value] }
        stmt.set(updates)

        connection.update(stmt)
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
                       Utils.define_model(table_name)
                     end
        end

        def connection
          model.connection
        end
    end
  end
end
