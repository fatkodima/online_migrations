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
        relation = model
          .where(copy_to.map { |to_column| [to_column, nil] }.to_h)

        Utils.ar_where_not_multiple_conditions(
          relation,
          copy_from.map { |from_column| [from_column, nil] }.to_h
        )
      end

      def process_batch(relation)
        arel = relation.arel
        arel_table = relation.arel_table

        old_values = copy_from.map do |from_column|
          old_value = arel_table[from_column]
          if (type_cast_function = type_cast_functions[from_column])
            if Utils.ar_version <= 5.2
              # ActiveRecord <= 5.2 does not support quoting of Arel::Nodes::NamedFunction
              old_value = Arel.sql("#{type_cast_function}(#{connection.quote_column_name(from_column)})")
            else
              old_value = Arel::Nodes::NamedFunction.new(type_cast_function, [old_value])
            end
          end
          old_value
        end

        if Utils.ar_version <= 4.2
          stmt = Arel::UpdateManager.new(arel.engine)
        else
          stmt = Arel::UpdateManager.new
        end

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
