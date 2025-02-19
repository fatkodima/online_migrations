# frozen_string_literal: true

module OnlineMigrations
  module BackgroundDataMigrations
    # @private
    class PerformActionOnRelation < DataMigration
      attr_reader :model, :conditions, :action, :options

      def initialize(model_name, conditions, action, options = {})
        @model = Object.const_get(model_name, false)
        @conditions = conditions
        @action = action.to_sym
        @options = options.symbolize_keys
      end

      def collection
        model.unscoped.where(conditions).in_batches(of: 100)
      end

      def process(relation)
        case action
        when :update_all
          updates = options.fetch(:updates)
          relation.public_send(action, updates)
        when :delete_all, :destroy_all
          relation.public_send(action)
        else
          relation.each(&action)
        end
      end
    end
  end
end
