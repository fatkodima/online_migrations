# frozen_string_literal: true

module OnlineMigrations
  # @private
  module SchemaCache
    def primary_keys(table_name)
      if renamed_tables.key?(table_name)
        super(renamed_tables[table_name])
      elsif renamed_columns.key?(table_name)
        super(column_rename_table(table_name))
      else
        super
      end
    end

    def columns(table_name)
      if renamed_tables.key?(table_name)
        super(renamed_tables[table_name])
      elsif renamed_columns.key?(table_name)
        columns = super(column_rename_table(table_name))
        renamed_columns[table_name].each do |old_column_name, new_column_name|
          duplicate_column(old_column_name, new_column_name, columns)
        end
        columns
      else
        super.reject { |column| column.name.end_with?("_for_type_change") }
      end
    end

    def indexes(table_name)
      # Available only in Active Record 6.0+
      return if !defined?(super)

      if renamed_tables.key?(table_name)
        super(renamed_tables[table_name])
      elsif renamed_columns.key?(table_name)
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
      if renamed_tables.key?(name)
        super(renamed_tables[name])
      end

      if renamed_columns.key?(name)
        super(column_rename_table(name))
      end

      super(name)
      clear_renames_cache!
    end

    private
      def renamed_tables
        @renamed_tables ||= begin
          table_renames = OnlineMigrations.config.table_renames
          views = connection.views
          table_renames.select do |old_name, _|
            views.include?(old_name)
          end
        end
      end

      def renamed_columns
        @renamed_columns ||= begin
          column_renames = OnlineMigrations.config.column_renames
          views = connection.views
          column_renames.select do |table_name, _|
            views.include?(table_name)
          end
        end
      end

      def column_rename_table(table_name)
        "#{table_name}_column_rename"
      end

      def clear_renames_cache!
        @renamed_columns = nil
        @renamed_tables = nil
      end

      def duplicate_column(old_column_name, new_column_name, columns)
        old_column = columns.find { |column| column.name == old_column_name }
        new_column = old_column.dup
        # ActiveRecord defines only reader for :name
        new_column.instance_variable_set(:@name, new_column_name)
        # Correspond to the ActiveRecord freezing of each column
        columns << new_column.freeze
      end
  end
end
