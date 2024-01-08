# frozen_string_literal: true

require "delegate"

module OnlineMigrations
  module SchemaDumper
    def initialize(connection, options = {})
      if OnlineMigrations.config.alphabetize_schema
        connection = WrappedConnection.new(connection)
      end

      super
    end
  end

  class WrappedConnection < SimpleDelegator
    def columns(table_name)
      super.sort_by(&:name)
    end
  end
end
