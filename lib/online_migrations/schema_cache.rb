# frozen_string_literal: true

module OnlineMigrations
  # @private
  module SchemaCache
    def primary_keys(connection, table_name)
      if (renamed_table = renamed_table?(connection, table_name))
        super(connection, renamed_table)
      elsif renamed_column?(connection, table_name)
        super(connection, column_rename_table(table_name))
      else
        super
      end
    end

    def columns(connection, table_name)
      if (renamed_table = renamed_table?(connection, table_name))
        super(connection, renamed_table)
      elsif renamed_column?(connection, table_name)
        columns = super(connection, column_rename_table(table_name))
        OnlineMigrations.config.column_renames[table_name].each do |old_column_name, new_column_name|
          duplicate_column(old_column_name, new_column_name, columns)
        end
        columns
      else
        super.reject { |column| column.name.end_with?("_for_type_change") }
      end
    end

    def indexes(connection, table_name)
      if (renamed_table = renamed_table?(connection, table_name))
        super(connection, renamed_table)
      elsif renamed_column?(connection, table_name)
        super(connection, column_rename_table(table_name))
      else
        super
      end
    end

    def clear_data_source_cache!(connection, name)
      if (renamed_table = renamed_table?(connection, name))
        super(connection, renamed_table)
      end

      if renamed_column?(connection, name)
        super(connection, column_rename_table(name))
      end

      super
    end

    private
      def renamed_table?(connection, table_name)
        table_renames = OnlineMigrations.config.table_renames
        if table_renames.key?(table_name) && connection.view_exists?(table_name)
          table_renames[table_name]
        end
      end

      def renamed_column?(connection, table_name)
        column_renames = OnlineMigrations.config.column_renames
        column_renames.key?(table_name) && connection.view_exists?(table_name)
      end

      def column_rename_table(table_name)
        "#{table_name}_column_rename"
      end

      def duplicate_column(old_column_name, new_column_name, columns)
        old_column = columns.find { |column| column.name == old_column_name }
        new_column = old_column.dup
        # Active Record defines only reader for :name
        new_column.instance_variable_set(:@name, new_column_name)
        # Correspond to the Active Record freezing of each column
        columns << new_column.freeze
      end
  end

  # @private
  module SchemaCache72
    # Active Record >= 7.2 changed signature of the methods,
    # see https://github.com/rails/rails/pull/48716.
    def primary_keys(pool, table_name)
      if (renamed_table = renamed_table?(pool, table_name))
        super(pool, renamed_table)
      elsif renamed_column?(pool, table_name)
        super(pool, column_rename_table(table_name))
      else
        super
      end
    end

    def columns(pool, table_name)
      if (renamed_table = renamed_table?(pool, table_name))
        super(pool, renamed_table)
      elsif renamed_column?(pool, table_name)
        columns = super(pool, column_rename_table(table_name))
        OnlineMigrations.config.column_renames[table_name].each do |old_column_name, new_column_name|
          duplicate_column(old_column_name, new_column_name, columns)
        end
        columns
      else
        super.reject { |column| column.name.end_with?("_for_type_change") }
      end
    end

    def indexes(pool, table_name)
      if (renamed_table = renamed_table?(pool, table_name))
        super(pool, renamed_table)
      elsif renamed_column?(pool, table_name)
        super(pool, column_rename_table(table_name))
      else
        super
      end
    end

    def clear_data_source_cache!(pool, name)
      if (renamed_table = renamed_table?(pool, name))
        super(pool, renamed_table)
      end

      if renamed_column?(pool, name)
        super(pool, column_rename_table(name))
      end

      super
    end

    private
      def renamed_table?(pool, table_name)
        table_renames = OnlineMigrations.config.table_renames
        if table_renames.key?(table_name)
          view_exists = pool.with_connection do |connection|
            connection.view_exists?(table_name)
          end

          table_renames[table_name] if view_exists
        end
      end

      def renamed_column?(pool, table_name)
        column_renames = OnlineMigrations.config.column_renames
        return false if !column_renames.key?(table_name)

        pool.with_connection do |connection|
          connection.view_exists?(table_name)
        end
      end

      def column_rename_table(table_name)
        "#{table_name}_column_rename"
      end

      def duplicate_column(old_column_name, new_column_name, columns)
        old_column = columns.find { |column| column.name == old_column_name }
        new_column = old_column.dup
        # Active Record defines only reader for :name
        new_column.instance_variable_set(:@name, new_column_name)
        # Correspond to the Active Record freezing of each column
        columns << new_column.freeze
      end
  end
end
