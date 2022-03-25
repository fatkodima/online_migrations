# frozen_string_literal: true

module OnlineMigrations
  module BackgroundMigrations
    # @private
    class PerformActionOnRelation < BackgroundMigration
      attr_reader :model, :conditions, :action, :options

      def initialize(model_name, conditions, action, options = {})
        @model = Object.const_get(model_name, false)
        @conditions = conditions
        @action = action.to_sym
        @options = options.symbolize_keys
      end

      def relation
        model.unscoped.where(conditions)
      end

      def process_batch(relation)
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
