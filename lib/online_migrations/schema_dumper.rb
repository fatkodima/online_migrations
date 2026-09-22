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
      columns = super

      if Utils.ar_version >= 8.2 && columns.is_a?(Hash)
        columns.transform_values { |v| v.sort_by(&:name) }
      else
        columns.sort_by(&:name)
      end
    end
  end
end
