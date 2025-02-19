# frozen_string_literal: true

module OnlineMigrations
  module ShardAware
    extend ActiveSupport::Concern

    included do
      before_validation :set_connection_class_name
    end

    def on_shard_if_present(&block)
      if shard
        connection_class.connected_to(shard: shard.to_sym, role: :writing, &block)
      else
        yield
      end
    end

    def connection_class_name=(value)
      if value && (klass = value.safe_constantize)
        if !(klass <= ActiveRecord::Base)
          raise ArgumentError, "connection_class_name is not an ActiveRecord::Base child class"
        end

        connection_class = Utils.find_connection_class(klass)
        super(connection_class.name)
      end
    end

    # @private
    def connection_class
      if connection_class_name && (klass = connection_class_name.safe_constantize)
        Utils.find_connection_class(klass)
      else
        ActiveRecord::Base
      end
    end

    private
      def set_connection_class_name
        self.connection_class_name ||= "ActiveRecord::Base"
      end
  end
end
