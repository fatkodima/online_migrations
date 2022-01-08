# frozen_string_literal: true

module OnlineMigrations
  # @private
  module ForeignKeyDefinition
    def defined_for?(*args, **options)
      super(*args, **options.except(:validate))
    end
  end
end
