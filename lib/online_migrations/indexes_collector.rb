# frozen_string_literal: true

module OnlineMigrations
  # @private
  class IndexesCollector
    COLUMN_TYPES = [:bigint, :binary, :boolean, :date, :datetime, :decimal,
                    :float, :integer, :json, :string, :text, :time, :timestamp, :virtual]

    attr_reader :indexes

    def initialize
      @indexes = []
    end

    def collect
      yield self
    end

    def index(_column_name, **options)
      @indexes << IndexDefinition.new(using: options[:using].to_s)
    end

    def references(*_ref_names, **options)
      index = options.fetch(:index, true)

      if index
        using = index.is_a?(Hash) ? index[:using].to_s : nil
        @indexes << IndexDefinition.new(using: using)
      end
    end
    alias belongs_to references

    def method_missing(method_name, *_args, **options)
      # Check for type-based methods, where we can also specify an index:
      # t.string :email, index: true
      if COLUMN_TYPES.include?(method_name)
        index = options.fetch(:index, false)

        if index
          using = index.is_a?(Hash) ? index[:using].to_s : nil
          @indexes << IndexDefinition.new(using: using)
        end
      end
    end
  end
end
