# frozen_string_literal: true

module OnlineMigrations
  # @private
  module SchemaCache
    def primary_keys(table_name)
      if renamed_columns.key?(table_name)
        super(column_rename_table(table_name))
      else
        super
      end
    end

    def columns(table_name)
      if renamed_columns.key?(table_name)
        columns = super(column_rename_table(table_name))

        old_column_name, new_column_name = renamed_columns[table_name].first.to_a

        old_column = columns.find { |column| column.name == old_column_name }
        new_column = old_column.dup

        # ActiveRecord defines only reader for :name
        new_column.instance_variable_set(:@name, new_column_name)

        # Correspond to the ActiveRecord freezing of each column
        columns << new_column.freeze
      else
        super
      end
    end

    def indexes(table_name)
      if renamed_columns.key?(table_name)
        super(column_rename_table(table_name))
      else
        super
      end
    end

    def clear!
      super
      clear_renames_cache!
    end

    def clear_data_source_cache!(name)
      if renamed_columns.key?(name)
        super(column_rename_table(name))
      end

      super(name)
      clear_renames_cache!
    end

    private
      def renamed_columns
        @renamed_columns ||= begin
          column_renames = OnlineMigrations.config.column_renames
          column_renames.select do |table_name, _|
            connection.views.include?(table_name)
          end
        end
      end

      def column_rename_table(table_name)
        "#{table_name}_column_rename"
      end

      def clear_renames_cache!
        @renamed_columns = nil
      end
  end
end
