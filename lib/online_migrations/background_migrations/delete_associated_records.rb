# frozen_string_literal: true

module OnlineMigrations
  module BackgroundMigrations
    # @private
    class DeleteAssociatedRecords < BackgroundMigration
      attr_reader :record, :association

      def initialize(model_name, record_id, association, _options = {})
        model = Object.const_get(model_name, false)
        @record = model.find(record_id)
        @association = association
      end

      def relation
        unless @record.respond_to?(association)
          raise ArgumentError, "'#{@record.class.name}' has no association called '#{association}'"
        end

        record.public_send(association)
      end

      def process_batch(relation)
        relation.delete_all(:delete_all)
      end
    end
  end
end
