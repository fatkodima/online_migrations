# frozen_string_literal: true

module OnlineMigrations
  # To safely change the type of the column, we need to perform the following steps:
  #   1. create a new column based on the old one (covered by `initialize_column_type_change`)
  #   2. ensure data stays in sync (via triggers) (covered by `initialize_column_type_change`)
  #   3. backfill data from the old column (`backfill_column_for_type_change`)
  #   4. copy indexes, foreign keys, check constraints, NOT NULL constraint,
  #     make new column a Primary Key if we change type of the primary key column,
  #     swap new column in place (`finalize_column_type_change`)
  #   5. remove copy trigger and old column (`cleanup_column_type_change`)
  #
  # For example, suppose we need to change `files`.`size` column's type from `integer` to `bigint`:
  #
  # 1. Create a new column and keep data in sync
  #   ```
  #     class InitializeFilesSizeTypeChangeToBigint < ActiveRecord::Migration
  #       def change
  #         initialize_column_type_change(:files, :size, :bigint)
  #       end
  #     end
  #   ```
  #
  # 2. Backfill data
  #   ```
  #     class BackfillFilesSizeTypeChangeToBigint < ActiveRecord::Migration
  #       def up
  #         backfill_column_for_type_change(:files, :size, progress: true)
  #       end
  #
  #       def down
  #         # no op
  #       end
  #     end
  #   ```
  #
  # 3. Copy indexes, foreign keys, check constraints, NOT NULL constraint, swap new column in place
  #   ```
  #     class FinalizeFilesSizeTypeChangeToBigint < ActiveRecord::Migration
  #       def change
  #         finalize_column_type_change(:files, :size)
  #       end
  #     end
  #   ```
  #
  # 4. Finally, if everything is working as expected, remove copy trigger and old column
  #   ```
  #     class CleanupFilesSizeTypeChangeToBigint < ActiveRecord::Migration
  #       def up
  #         cleanup_column_type_change(:files, :size)
  #       end
  #
  #       def down
  #         initialize_column_type_change(:files, :size, :integer)
  #       end
  #     end
  #   ```
  #
  module ChangeColumnTypeHelpers
    # Initialize the process of changing column type. Creates a new column from
    # the old one and ensures that data stays in sync.
    #
    # @param table_name [String, Symbol]
    # @param column_name [String, Symbol]
    # @param new_type [String, Symbol]
    # @param options [Hash] additional options that apply to a new type, `:limit` for example
    #
    # @return [void]
    #
    # @example
    #   initialize_column_type_change(:files, :size, :bigint)
    #
    # @example With additional column options
    #   initialize_column_type_change(:users, :name, :string, limit: 64)
    #
    def initialize_column_type_change(table_name, column_name, new_type, **options)
      initialize_columns_type_change(table_name, [[column_name, new_type]], column_name => options)
    end

    # Same as `initialize_column_type_change` but for multiple columns at once
    #
    # This is useful to avoid multiple costly disk rewrites of large tables
    # when changing type of each column separately.
    #
    # @param table_name [String, Symbol]
    # @param columns_and_types [Array<Array<(Symbol, Symbol)>>] columns and new types,
    #   represented as nested arrays. Example: `[[:id, :bigint], [:name, :string]]`
    # @param options [Hash] keys - column names, values -
    #   options for specific columns (additional options that apply to a new type, `:limit` for example)
    #
    # @see #initialize_column_type_change
    #
    def initialize_columns_type_change(table_name, columns_and_types, **options)
      if !columns_and_types.is_a?(Array) || !columns_and_types.all? { |e| e.is_a?(Array) }
        raise ArgumentError, "columns_and_types must be an array of arrays"
      end

      conversions = columns_and_types.map do |(column_name, _new_type)|
        [column_name, __change_type_column(column_name)]
      end.to_h

      if (extra_keys = (options.keys - conversions.keys)).any?
        raise ArgumentError, "Options has unknown keys: #{extra_keys.map(&:inspect).join(', ')}. " \
                             "Can contain only column names: #{conversions.keys.map(&:inspect).join(', ')}."
      end

      transaction do
        columns_and_types.each do |(column_name, new_type)|
          old_col = __column_for(table_name, column_name)
          old_col_options = __options_from_column(old_col, [:collation, :comment])
          column_options = options[column_name] || {}
          tmp_column_name = conversions[column_name]

          if raw_connection.server_version >= 11_00_00
            if primary_key(table_name) == column_name.to_s && old_col.type == :integer
              # If the column to be converted is a Primary Key, set it to
              # `NOT NULL DEFAULT 0` and we'll copy the correct values when backfilling.
              # That way, we skip the expensive validation step required to add
              #  a `NOT NULL` constraint at the end of the process.
              add_column(table_name, tmp_column_name, new_type,
                **old_col_options.merge(column_options).merge(default: old_col.default || 0, null: false))
            else
              unless old_col.default.nil?
                old_col_options = old_col_options.merge(default: old_col.default, null: old_col.null)
              end
              add_column(table_name, tmp_column_name, new_type, **old_col_options.merge(column_options))
            end
          else
            add_column(table_name, tmp_column_name, new_type, **old_col_options.merge(column_options))
            change_column_default(table_name, tmp_column_name, old_col.default) unless old_col.default.nil?
          end
        end

        __create_copy_triggers(table_name, conversions.keys, conversions.values)
      end
    end

    # Reverts operations performed by initialize_column_type_change
    #
    # @param table_name [String, Symbol]
    # @param column_name [String, Symbol]
    # @param _new_type [String, Symbol] Passing this argument will make this change reversible in migration
    # @param _options [Hash] additional options that apply to a new type.
    #     Passing this argument will make this change reversible in migration
    #
    # @return [void]
    #
    # @example
    #   revert_initialize_column_type_change(:files, :size)
    #
    def revert_initialize_column_type_change(table_name, column_name, _new_type = nil, **_options)
      cleanup_column_type_change(table_name, column_name)
    end

    # Same as `revert_initialize_column_type_change` but for multiple columns.
    # @see #revert_initialize_column_type_change
    #
    def revert_initialize_columns_type_change(table_name, columns_and_types, **_options)
      column_names = columns_and_types.map(&:first)
      cleanup_columns_type_change(table_name, *column_names)
    end

    # Backfills data from the old column to the new column.
    #
    # @param table_name [String, Symbol]
    # @param column_name [String, Symbol]
    # @param type_cast_function [String, Symbol] Some type changes require casting data to a new type.
    #     For example when changing from `text` to `jsonb`. In this case, use the `type_cast_function` option.
    #     You need to make sure there is no bad data and the cast will always succeed
    # @param options [Hash] used to control the behavior of `update_column_in_batches`
    # @return [void]
    #
    # @example
    #   backfill_column_for_type_change(:files, :size)
    #
    # @example With type casting
    #   backfill_column_for_type_change(:users, :settings, type_cast_function: "jsonb")
    #
    # @example Additional batch options
    #   backfill_column_for_type_change(:files, :size, batch_size: 10_000)
    #
    # @note This method should not be run within a transaction
    # @note For large tables (10/100s of millions of records)
    #   it is recommended to use `backfill_column_for_type_change_in_background`.
    #
    def backfill_column_for_type_change(table_name, column_name, type_cast_function: nil, **options)
      backfill_columns_for_type_change(table_name, column_name,
          type_cast_functions: { column_name => type_cast_function }, **options)
    end

    # Same as `backfill_column_for_type_change` but for multiple columns.
    #
    # @param type_cast_functions [Hash] if not empty, keys - column names,
    #   values - corresponding type cast functions
    #
    # @see #backfill_column_for_type_change
    #
    def backfill_columns_for_type_change(table_name, *column_names, type_cast_functions: {}, **options)
      conversions = column_names.map do |column_name|
        tmp_column = __change_type_column(column_name)

        old_value = Arel::Table.new(table_name)[column_name]
        if (type_cast_function = type_cast_functions.with_indifferent_access[column_name])
          old_value = Arel::Nodes::NamedFunction.new(type_cast_function.to_s, [old_value])
        end

        [tmp_column, old_value]
      end

      update_columns_in_batches(table_name, conversions, **options)
    end

    # Copies `NOT NULL` constraint, indexes, foreign key, and check constraints
    # from the old column to the new column
    #
    # Note: If a column contains one or more indexes that don't contain the name of the original column,
    # this procedure will fail. In that case, you'll first need to rename these indexes.
    #
    # @example
    #   finalize_column_type_change(:files, :size)
    #
    # @note This method should not be run within a transaction
    #
    def finalize_column_type_change(table_name, column_name)
      finalize_columns_type_change(table_name, column_name)
    end

    # Same as `finalize_column_type_change` but for multiple columns
    # @see #finalize_column_type_change
    #
    def finalize_columns_type_change(table_name, *column_names)
      __ensure_not_in_transaction!

      conversions = column_names.map do |column_name|
        [column_name.to_s, __change_type_column(column_name)]
      end.to_h

      conversions.each do |column_name, tmp_column_name|
        old_column = __column_for(table_name, column_name)
        column = __column_for(table_name, tmp_column_name)

        # We already set default and NOT NULL for to-be-PK columns
        # for PG >= 11, so can skip this case
        if !old_column.null && column.null
          add_not_null_constraint(table_name, tmp_column_name, validate: false)
          validate_not_null_constraint(table_name, tmp_column_name)

          # At this point we are sure there are no NULLs in this column
          transaction do
            # For PG < 11 and Primary Key conversions, setting a column as the PK
            # converts even check constraints to NOT NULL column constraints
            # and forces an inline re-verification of the whole table.
            #
            # For PG >= 12 we can "promote" CHECK constraint to NOT NULL constraint,
            # but for older versions we can set attribute as NOT NULL directly
            # through PG internal tables.
            # In-depth analysis of implications of this was made, so this approach
            # is considered safe - https://habr.com/ru/company/haulmont/blog/493954/  (in russian).
            execute(<<-SQL.strip_heredoc)
              UPDATE pg_catalog.pg_attribute
              SET attnotnull = true
              WHERE attrelid = #{quote(table_name)}::regclass
                AND attname = #{quote(tmp_column_name)}
            SQL

            remove_not_null_constraint(table_name, tmp_column_name)
          end
        end

        __copy_indexes(table_name, column_name, tmp_column_name)
        __copy_foreign_keys(table_name, column_name, tmp_column_name)
        __copy_check_constraints(table_name, column_name, tmp_column_name)

        if primary_key(table_name) == column_name
          __finalize_primary_key_type_change(table_name, column_name, column_names)
        end
      end

      # Swap all non-PK columns at once, because otherwise when this helper possibly
      # will have a need to be rerun, it will be impossible to know which columns
      # already were swapped and which were not.
      transaction do
        conversions
          .reject { |column_name, _tmp_column_name| column_name == primary_key(table_name) }
          .each do |column_name, tmp_column_name|
            swap_column_names(table_name, column_name, tmp_column_name)
          end

        __reset_trigger_function(table_name, column_names)
      end
    end

    # Reverts operations performed by `finalize_column_type_change`
    #
    # @param table_name [String, Symbol]
    # @param column_name [String, Symbol]
    # @return [void]
    #
    # @example
    #   revert_finalize_column_type_change(:files, :size)
    #
    def revert_finalize_column_type_change(table_name, column_name)
      revert_finalize_columns_type_change(table_name, column_name)
    end

    # Same as `revert_finalize_column_type_change` but for multiple columns
    # @see #revert_finalize_column_type_change
    #
    def revert_finalize_columns_type_change(table_name, *column_names)
      __ensure_not_in_transaction!

      conversions = column_names.map do |column_name|
        [column_name.to_s, __change_type_column(column_name)]
      end.to_h

      transaction do
        conversions
          .reject { |column_name, _tmp_column_name| column_name == primary_key(table_name) }
          .each do |column_name, tmp_column_name|
            swap_column_names(table_name, column_name, tmp_column_name)
          end

        __reset_trigger_function(table_name, column_names)
      end

      conversions.each do |column_name, tmp_column_name|
        indexes(table_name).each do |index|
          if index.columns.include?(tmp_column_name)
            remove_index(table_name, tmp_column_name, algorithm: :concurrently)
          end
        end

        foreign_keys(table_name).each do |fk|
          if fk.column == tmp_column_name
            remove_foreign_key(table_name, column: tmp_column_name)
          end
        end

        __check_constraints_for(table_name, tmp_column_name).each do |constraint|
          remove_check_constraint(table_name, name: constraint.constraint_name)
        end

        if primary_key(table_name) == column_name
          __finalize_primary_key_type_change(table_name, column_name, column_names)
        end
      end
    end

    # Finishes the process of column type change
    #
    # This helper removes copy triggers and old column.
    #
    # @param table_name [String, Symbol]
    # @param column_name [String, Symbol]
    # @return [void]
    #
    # @example
    #   cleanup_column_type_change(:files, :size)
    #
    # @note This method is not reversible by default in migrations.
    #   You need to use `initialize_column_type_change` in `down` method with
    #   the original column type to be able to revert.
    #
    def cleanup_column_type_change(table_name, column_name)
      cleanup_columns_type_change(table_name, column_name)
    end

    # Same as `cleanup_column_type_change` but for multiple columns
    # @see #cleanup_column_type_change
    #
    def cleanup_columns_type_change(table_name, *column_names)
      conversions = column_names.map do |column_name|
        [column_name, __change_type_column(column_name)]
      end.to_h

      transaction do
        __remove_copy_triggers(table_name, conversions.keys, conversions.values)
        remove_columns(table_name, *conversions.values)
      end
    end

    private
      def __change_type_column(column_name)
        "#{column_name}_for_type_change"
      end

      def __options_from_column(column, options)
        result = {}
        options.each do |option|
          if column.respond_to?(option)
            value = column.public_send(option)
            result[option] = value unless value.nil?
          end
        end
        result
      end

      def __copy_triggers_name(table_name, from_column, to_column)
        CopyTrigger.on_table(table_name, connection: self).name(from_column, to_column)
      end

      def __create_copy_triggers(table_name, from_column, to_column)
        CopyTrigger.on_table(table_name, connection: self).create(from_column, to_column)
      end

      def __remove_copy_triggers(table_name, from_column, to_column)
        CopyTrigger.on_table(table_name, connection: self).remove(from_column, to_column)
      end

      def __copy_indexes(table_name, from_column, to_column)
        from_column  = from_column.to_s
        to_column    = to_column.to_s

        __indexes_for(table_name, from_column).each do |index|
          new_columns = index.columns.map do |column|
            column == from_column ? to_column : column
          end

          # This is necessary as we can't properly rename indexes such as "taggings_idx".
          unless index.name.include?(from_column)
            raise "The index #{index.name} can not be copied as it does not " \
                  "mention the old column. You have to rename this index manually first."
          end

          name = index.name.gsub(from_column, to_column)

          options = {
            unique: index.unique,
            name: name,
            length: index.lengths,
            order: index.orders,
          }

          options[:using] = index.using if index.using
          options[:where] = index.where if index.where

          # Opclasses were added in 5.2
          if Utils.ar_version >= 5.2 && !index.opclasses.blank?
            opclasses = index.opclasses.dup

            # Copy the operator classes for the old column (if any) to the new column.
            opclasses[to_column] = opclasses.delete(from_column) if opclasses[from_column]

            options[:opclass] = opclasses
          end

          add_index(table_name, new_columns, **options.merge(algorithm: :concurrently))
        end
      end

      def __indexes_for(table_name, column_name)
        column_name = column_name.to_s

        indexes(table_name).select { |index| index.columns.include?(column_name) }
      end

      # While its rare for a column to have multiple foreign keys, PostgreSQL supports this.
      #
      # One of the examples is when changing type of the referenced column
      # with zero-downtime, we can have a column referencing both old column
      # and new column, until the full migration is done.
      def __copy_foreign_keys(table_name, from_column, to_column)
        __foreign_keys_for(table_name, from_column).each do |fk|
          __copy_foreign_key(fk, to_column)
        end
      end

      def __foreign_keys_for(table_name, column_name)
        foreign_keys(table_name).select { |fk| fk.column == column_name.to_s }
      end

      def __copy_check_constraints(table_name, from_column, to_column)
        __check_constraints_for(table_name, from_column).each do |check|
          expression = check["constraint_def"][/CHECK \({2}(.+)\){2}/, 1]
          new_expression = expression.gsub(from_column.to_s, to_column.to_s)

          add_check_constraint(table_name, new_expression, validate: false)

          if check["valid"]
            validate_check_constraint(table_name, expression: new_expression)
          end
        end
      end

      def __check_constraints_for(table_name, column_name)
        __check_constraints(table_name).select { |c| c["column_name"] == column_name }
      end

      def __check_constraints(table_name)
        schema = __schema_for_table(table_name)

        check_sql = <<-SQL.strip_heredoc
          SELECT
            ccu.column_name as column_name,
            con.conname as constraint_name,
            pg_get_constraintdef(con.oid) as constraint_def,
            con.convalidated AS valid
          FROM pg_catalog.pg_constraint con
            INNER JOIN pg_catalog.pg_class rel
              ON rel.oid = con.conrelid
            INNER JOIN pg_catalog.pg_namespace nsp
              ON nsp.oid = con.connamespace
            INNER JOIN information_schema.constraint_column_usage ccu
              ON con.conname = ccu.constraint_name
                AND rel.relname = ccu.table_name
          WHERE rel.relname = #{quote(table_name)}
            AND con.contype = 'c'
            AND nsp.nspname = #{schema}
        SQL

        select_all(check_sql)
      end

      def __rename_constraint(table_name, old_name, new_name)
        execute(<<-SQL.strip_heredoc)
          ALTER TABLE #{quote_table_name(table_name)}
          RENAME CONSTRAINT #{quote_column_name(old_name)} TO #{quote_column_name(new_name)}
        SQL
      end

      def __finalize_primary_key_type_change(table_name, column_name, column_names)
        quoted_table_name = quote_table_name(table_name)
        quoted_column_name = quote_column_name(column_name)
        tmp_column_name = __change_type_column(column_name)

        # This is to replace the existing "<table_name>_pkey" index
        pkey_index_name = "index_#{table_name}_for_pkey"
        add_index(table_name, tmp_column_name, unique: true, algorithm: :concurrently, name: pkey_index_name)

        __replace_referencing_foreign_keys(table_name, column_name, tmp_column_name)

        transaction do
          # Lock the table explicitly to prevent new rows being inserted
          execute("LOCK TABLE #{quoted_table_name} IN ACCESS EXCLUSIVE MODE")

          swap_column_names(table_name, column_name, tmp_column_name)

          # We need to update the trigger function in order to make PostgreSQL to
          # regenerate the execution plan for it. This is to avoid type mismatch errors like
          # "type of parameter 15 (bigint) does not match that when preparing the plan (integer)"
          __reset_trigger_function(table_name, column_names)

          # Transfer ownership of the primary key sequence
          sequence_name = "#{table_name}_#{column_name}_seq"
          execute("ALTER SEQUENCE #{quote_table_name(sequence_name)} OWNED BY #{quoted_table_name}.#{quoted_column_name}")
          execute("ALTER TABLE #{quoted_table_name} ALTER COLUMN #{quoted_column_name} SET DEFAULT nextval(#{quote(sequence_name)}::regclass)")
          change_column_default(table_name, tmp_column_name, nil)

          # Replace the primary key constraint
          pkey_constraint_name = "#{table_name}_pkey"
          # CASCADE is not used here because the old FKs should be removed already
          execute("ALTER TABLE #{quoted_table_name} DROP CONSTRAINT #{quote_table_name(pkey_constraint_name)}")
          rename_index(table_name, pkey_index_name, pkey_constraint_name)
          execute("ALTER TABLE #{quoted_table_name} ADD CONSTRAINT #{quote_table_name(pkey_constraint_name)} PRIMARY KEY USING INDEX #{quote_table_name(pkey_constraint_name)}")
        end
      end

      # Replaces existing FKs in other tables referencing this table's old column
      # with new ones referencing a new column.
      def __replace_referencing_foreign_keys(table_name, from_column, to_column)
        referencing_table_names = __referencing_table_names(table_name)

        referencing_table_names.each do |referencing_table_name|
          foreign_keys(referencing_table_name).each do |fk|
            if fk.to_table == table_name.to_s && fk.primary_key == from_column
              existing_name = fk.name
              tmp_name = "#{existing_name}_tmp"
              __copy_foreign_key(fk, fk.column, primary_key: to_column, name: tmp_name)

              transaction do
                # We'll need ACCESS EXCLUSIVE lock on the related tables,
                # lets make sure it can be acquired from the start.
                execute("LOCK TABLE #{table_name}, #{referencing_table_name} IN ACCESS EXCLUSIVE MODE")

                remove_foreign_key(referencing_table_name, name: existing_name)
                __rename_constraint(referencing_table_name, tmp_name, existing_name)
              end
            end
          end
        end
      end

      # Returns tables that have a FK to the given table
      def __referencing_table_names(table_name)
        schema = __schema_for_table(table_name)

        select_values(<<-SQL.strip_heredoc)
          SELECT DISTINCT con.conrelid::regclass::text AS conrelname
          FROM pg_catalog.pg_constraint con
            INNER JOIN pg_catalog.pg_namespace nsp
                ON nsp.oid = con.connamespace
          WHERE con.confrelid = #{quote(table_name)}::regclass
            AND con.contype = 'f'
            AND nsp.nspname = #{schema}
          ORDER BY 1
        SQL
      end

      def __reset_trigger_function(table_name, column_names)
        tmp_column_names = column_names.map { |c| __change_type_column(c) }
        function_name = __copy_triggers_name(table_name, column_names, tmp_column_names)
        execute("ALTER FUNCTION #{quote_table_name(function_name)}() RESET ALL")
      end
  end
end
