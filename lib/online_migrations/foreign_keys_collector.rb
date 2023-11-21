# frozen_string_literal: true

module OnlineMigrations
  # @private
  class ForeignKeysCollector
    attr_reader :referenced_tables

    def initialize
      @referenced_tables = Set.new
    end

    def collect
      yield self
    end

    def foreign_key(to_table, **_options)
      @referenced_tables << to_table.to_s
    end

    def references(*ref_names, **options)
      if options[:foreign_key]
        ref_names.each do |ref_name|
          @referenced_tables << Utils.foreign_table_name(ref_name, options)
        end
      end
    end
    alias belongs_to references

    def method_missing(*)
      # we only care about foreign keys related methods
    end
  end
end
