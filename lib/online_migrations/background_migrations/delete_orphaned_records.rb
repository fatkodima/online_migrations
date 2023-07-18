# frozen_string_literal: true

module OnlineMigrations
  module BackgroundMigrations
    # @private
    class DeleteOrphanedRecords < BackgroundMigration
      attr_reader :model, :associations

      def initialize(model_name, associations, _options = {})
        @model = Object.const_get(model_name, false)
        @associations = associations.map(&:to_sym)
      end

      def relation
        # For Active Record 6.1+ we can use `where.missing`
        # https://github.com/rails/rails/pull/34727
        associations.inject(model.unscoped) do |relation, association|
          reflection = model.reflect_on_association(association)
          unless reflection
            raise ArgumentError, "'#{model.name}' has no association called '#{association}'"
          end

          # left_joins was added in Active Record 5.0 - https://github.com/rails/rails/pull/12071
          relation
            .left_joins(association)
            .where(reflection.table_name => { reflection.association_primary_key => nil })
        end
      end

      def process_batch(relation)
        if Utils.ar_version > 5.0
          relation.delete_all
        else
          # Older Active Record generates incorrect query when running delete_all
          primary_key = model.primary_key
          model.unscoped.where(primary_key => relation.select(primary_key)).delete_all
        end
      end

      def count
        Utils.estimated_count(model.connection, model.table_name)
      end
    end
  end
end
