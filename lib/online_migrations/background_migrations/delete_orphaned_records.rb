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
        model.unscoped.where.missing(*associations)
      end

      def process_batch(relation)
        relation.delete_all
      end

      def count
        Utils.estimated_count(model.connection, model.table_name)
      end
    end
  end
end
