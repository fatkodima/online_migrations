# frozen_string_literal: true

module OnlineMigrations
  # @private
  module ForeignKeyDefinition
    if Utils.ar_version <= 4.2
      def defined_for?(to_table: nil, **options)
        (to_table.nil? || to_table.to_s == self.to_table) &&
          options.all? { |k, v| self.options[k].to_s == v.to_s }
      end
    elsif Utils.ar_version <= 5.1
      def defined_for?(*args, **options)
        super(*args, **options.except(:validate))
      end
    end
  end
end
