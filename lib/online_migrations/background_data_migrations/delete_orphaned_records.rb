# frozen_string_literal: true

module OnlineMigrations
  module BackgroundDataMigrations
    # @private
    class DeleteOrphanedRecords < DataMigration
      attr_reader :model, :associations

      def initialize(model_name, associations, _options = {})
        @model = Object.const_get(model_name, false)
        @associations = associations.map(&:to_sym)
      end

      def collection
        model.unscoped.where.missing(*associations)
      end

      def process(record)
        record.destroy
      end
    end
  end
end
