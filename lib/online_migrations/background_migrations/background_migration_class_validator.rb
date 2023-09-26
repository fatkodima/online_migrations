# frozen_string_literal: true

module OnlineMigrations
  module BackgroundMigrations
    # @private
    class BackgroundMigrationClassValidator < ActiveModel::Validator
      def validate(record)
        relation = record.migration_relation
        migration_name = record.migration_name

        if !relation.is_a?(ActiveRecord::Relation)
          record.errors.add(
            :migration_name,
            "#{migration_name}#relation must return an ActiveRecord::Relation object"
          )
          return
        end

        if relation.joins_values.present? && !record.batch_column_name.to_s.include?(".")
          record.errors.add(
            :batch_column_name,
            "must be a fully-qualified column if you join a table"
          )
        end

        if relation.arel.orders.present? || relation.arel.taken.present?
          record.errors.add(
            :migration_name,
            "#{migration_name}#relation cannot use ORDER BY or LIMIT due to the way how iteration with a cursor is designed. " \
            "You can use other ways to limit the number of rows, e.g. a WHERE condition on the primary key column."
          )
        end
      end
    end
  end
end
