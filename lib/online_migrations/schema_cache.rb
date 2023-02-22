# frozen_string_literal: true

module OnlineMigrations
  # @private
  module SchemaCache
    def primary_keys(table_name)
      if (renamed_table = renamed_table?(table_name))
        super(renamed_table)
      elsif renamed_column?(table_name)
        super(column_rename_table(table_name))
      else
        super
      end
    end

    def columns(table_name)
      if (renamed_table = renamed_table?(table_name))
        super(renamed_table)
      elsif renamed_column?(table_name)
        columns = super(column_rename_table(table_name))
        OnlineMigrations.config.column_renames[table_name].each do |old_column_name, new_column_name|
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

      if (renamed_table = renamed_table?(table_name))
        super(renamed_table)
      elsif renamed_column?(table_name)
        super(column_rename_table(table_name))
      else
        super
      end
    end

    def clear_data_source_cache!(name)
      if (renamed_table = renamed_table?(name))
        super(renamed_table)
      end

      if renamed_column?(name)
        super(column_rename_table(name))
      end

      super(name)
    end

    private
      def renamed_table?(table_name)
        table_renames = OnlineMigrations.config.table_renames
        if table_renames.key?(table_name)
          views = connection.views
          table_renames[table_name] if views.include?(table_name)
        end
      end

      def renamed_column?(table_name)
        column_renames = OnlineMigrations.config.column_renames
        column_renames.key?(table_name) && connection.views.include?(table_name)
      end

      def column_rename_table(table_name)
        "#{table_name}_column_rename"
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
