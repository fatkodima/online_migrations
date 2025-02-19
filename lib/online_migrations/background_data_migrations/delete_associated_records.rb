# frozen_string_literal: true

module OnlineMigrations
  module BackgroundDataMigrations
    # @private
    class DeleteAssociatedRecords < DataMigration
      attr_reader :record, :association

      def initialize(model_name, record_id, association, _options = {})
        model = Object.const_get(model_name, false)
        @record = model.find(record_id)
        @association = association
      end

      def collection
        if !@record.respond_to?(association)
          raise ArgumentError, "'#{@record.class.name}' has no association called '#{association}'"
        end

        record.public_send(association).in_batches(of: 100)
      end

      def process(relation)
        relation.delete_all
      end

      def count
        record.public_send(association).count
      end
    end
  end
end
