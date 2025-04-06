# frozen_string_literal: true

module OnlineMigrations
  # @private
  class IndexDefinition
    attr_reader :table, :columns, :unique, :opclasses, :where, :type, :using

    def initialize(**options)
      @table = options[:table]
      @columns = Array(options[:columns]).map(&:to_s)
      @unique = options[:unique]
      @opclasses = options[:opclass] || {}
      @where = options[:where]
      @type = options[:type]
      @using = options[:using] || :btree
    end

    # @param other [OnlineMigrations::IndexDefinition, ActiveRecord::ConnectionAdapters::IndexDefinition]
    def intersect?(other)
      # For ActiveRecord::ConnectionAdapters::IndexDefinition is for expression indexes,
      # `columns` is a string
      table == other.table &&
        columns.intersect?(Array(other.columns))
    end

    # @param other [OnlineMigrations::IndexDefinition, ActiveRecord::ConnectionAdapters::IndexDefinition]
    def covered_by?(other)
      return false if type != other.type
      return false if using != other.using
      return false if where != other.where
      return false if other.respond_to?(:opclasses) && opclasses != other.opclasses

      if unique && !other.unique
        false
      else
        prefix?(self, other)
      end
    end

    private
      def prefix?(lhs, rhs)
        lhs_columns = Array(lhs.columns)
        rhs_columns = Array(rhs.columns)

        lhs_columns.count <= rhs_columns.count &&
          rhs_columns[0...lhs_columns.count] == lhs_columns
      end
  end
end
