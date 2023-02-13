# frozen_string_literal: true

module OnlineMigrations
  module SchemaStatements
    include ChangeColumnTypeHelpers
    include BackgroundMigrations::MigrationHelpers

    # Updates the value of a column in batches.
    #
    # @param table_name [String, Symbol]
    # @param column_name [String, Symbol]
    # @param value value for the column. It is typically a literal. To perform a computed
    #     update, an Arel literal can be used instead
    # @option options [Integer] :batch_size (1000) size of the batch
    # @option options [String, Symbol] :batch_column_name (primary key) option is for tables without primary key, in this
    #     case another unique integer column can be used. Example: `:user_id`
    # @option options [Proc, Boolean] :progress (false) whether to show progress while running.
    #   - when `true` - will show progress (prints "." for each batch)
    #   - when `false` - will not show progress
    #   - when `Proc` - will call the proc on each iteration with the batched relation as argument.
    #     Example: `proc { |_relation| print "." }`
    # @option options [Integer] :pause_ms (50) The number of milliseconds to sleep between each batch execution.
    #     This helps to reduce database pressure while running updates and gives time to do maintenance tasks
    #
    # @yield [relation] a block to be called to add extra conditions to the queries being executed
    # @yieldparam relation [ActiveRecord::Relation] an instance of `ActiveRecord::Relation`
    #     to add extra conditions to
    #
    # @return [void]
    #
    # @example
    #   update_column_in_batches(:users, :admin, false)
    #
    # @example With extra conditions
    #   update_column_in_batches(:users, :name, "Guest") do |relation|
    #     relation.where(name: nil)
    #   end
    #
    # @example From other column
    #   update_column_in_batches(:users, :name_for_type_change, Arel.sql("name"))
    #
    # @example With computed value
    #   truncated_name = Arel.sql("substring(name from 1 for 64)")
    #   update_column_in_batches(:users, :name, truncated_name) do |relation|
    #     relation.where("length(name) > 64")
    #   end
    #
    # @note This method should not be run within a transaction
    # @note Consider `update_columns_in_batches` when updating multiple columns
    #   to avoid rewriting the table multiple times.
    # @note For large tables (10/100s of millions of records)
    #   you may consider using `backfill_column_in_background` or `copy_column_in_background`.
    #
    def update_column_in_batches(table_name, column_name, value, **options, &block)
      update_columns_in_batches(table_name, [[column_name, value]], **options, &block)
    end

    # Same as `update_column_in_batches`, but for multiple columns.
    #
    # This is useful to avoid multiple costly disk rewrites of large tables
    # when updating each column separately.
    #
    # @param columns_and_values
    # columns_and_values is an array of arrays (first item is a column name, second - new value)
    #
    # @see #update_column_in_batches
    #
    def update_columns_in_batches(table_name, columns_and_values,
                                  batch_size: 1000, batch_column_name: primary_key(table_name), progress: false, pause_ms: 50)
      __ensure_not_in_transaction!

      if !columns_and_values.is_a?(Array) || !columns_and_values.all? { |e| e.is_a?(Array) }
        raise ArgumentError, "columns_and_values must be an array of arrays"
      end

      if progress
        if progress == true
          progress = ->(_) { print(".") }
        elsif !progress.respond_to?(:call)
          raise ArgumentError, "The progress body needs to be a callable."
        end
      end

      model = Utils.define_model(table_name, self)

      conditions = columns_and_values.map do |(column_name, value)|
        value = Arel.sql(value.call.to_s) if value.is_a?(Proc)

        # Ignore subqueries in conditions
        unless value.is_a?(Arel::Nodes::SqlLiteral) && value.to_s =~ /select\s+/i
          arel_column = model.arel_table[column_name]
          arel_column.not_eq(value).or(arel_column.eq(nil))
        end
      end.compact

      batch_relation = model.where(conditions.inject(:and))
      batch_relation = yield batch_relation if block_given?

      iterator = BatchIterator.new(batch_relation)
      iterator.each_batch(of: batch_size, column: batch_column_name) do |relation|
        updates =
          if Utils.ar_version <= 5.2
            columns_and_values.map do |(column_name, value)|
              rhs =
                # ActiveRecord <= 5.2 can't quote these - we need to handle these cases manually
                case value
                when Arel::Attributes::Attribute
                  quote_column_name(value.name)
                when Arel::Nodes::SqlLiteral
                  value
                when Arel::Nodes::NamedFunction
                  "#{value.name}(#{quote_column_name(value.expressions.first.name)})"
                when Proc
                  value.call
                else
                  quote(value)
                end

              "#{quote_column_name(column_name)} = #{rhs}"
            end.join(", ")
          else
            columns_and_values.map do |(column, value)|
              value = Arel.sql(value.call.to_s) if value.is_a?(Proc)
              [column, value]
            end.to_h
          end

        relation.update_all(updates)

        progress.call(relation) if progress

        sleep(pause_ms * 0.001) if pause_ms > 0
      end
    end

    # Renames a column without requiring downtime
    #
    # The technique is built on top of database views, using the following steps:
    #   1. Rename the table to some temporary name
    #   2. Create a VIEW using the old table name with addition of a new column as an alias of the old one
    #   3. Add a workaround for ActiveRecord's schema cache
    #
    # For example, to rename `name` column to `first_name` of the `users` table, we can run:
    #
    #     BEGIN;
    #     ALTER TABLE users RENAME TO users_column_rename;
    #     CREATE VIEW users AS SELECT *, first_name AS name FROM users;
    #     COMMIT;
    #
    # As database views do not expose the underlying table schema (default values, not null constraints,
    # indexes, etc), further steps are needed to update the application to use the new table name.
    # ActiveRecord heavily relies on this data, for example, to initialize new models.
    #
    # To work around this limitation, we need to tell ActiveRecord to acquire this information
    # from original table using the new table name (see notes).
    #
    # @param table_name [String, Symbol] table name
    # @param column_name [String, Symbol] the name of the column to be renamed
    # @param new_column_name [String, Symbol] new new name of the column
    #
    # @return [void]
    #
    # @example
    #   initialize_column_rename(:users, :name, :first_name)
    #
    # @note
    #   Prior to using this method, you need to register the database table so that
    #   it instructs ActiveRecord to fetch the database table information (for SchemaCache)
    #   using the original table name (if it's present). Otherwise, fall back to the old table name:
    #
    #   ```OnlineMigrations.config.column_renames[table_name] = { old_column_name => new_column_name }```
    #
    #   Deploy this change before proceeding with this helper.
    #   This is necessary to avoid errors during a zero-downtime deployment.
    #
    # @note None of the DDL operations involving original table name can be performed
    #   until `finalize_column_rename` is run
    #
    def initialize_column_rename(table_name, column_name, new_column_name)
      initialize_columns_rename(table_name, { column_name => new_column_name })
    end

    # Same as `initialize_column_rename` but for multiple columns.
    #
    # The technique is built on top of database views, using the following steps:
    #   1. Rename the table to some temporary name
    #   2. Create a VIEW using the old table name with addition of the new columns as an aliases of the old ones
    #   3. Add a workaround for ActiveRecord's schema cache
    #
    # @param table_name [String, Symbol] table name
    # @param old_new_column_hash [Hash] the hash of old and new columns
    #
    # @return [void]
    #
    # @example
    #   initialize_columns_rename(:users, {fname: :first_name, lname: :last_name})
    #
    # @note
    #   Prior to using this method, you need to register the database table so that
    #   it instructs ActiveRecord to fetch the database table information (for SchemaCache)
    #   using the original table name (if it's present). Otherwise, fall back to the old table name:
    #
    #   ```OnlineMigrations.config.column_renames[table_name] = { old_column_name => new_column_name }```
    #
    #   Deploy this change before proceeding with this helper.
    #   This is necessary to avoid errors during a zero-downtime deployment.
    #
    # @note None of the DDL operations involving original table name can be performed
    #   until `finalize_column_rename` is run
    #
    def initialize_columns_rename(table_name, old_new_column_hash)
      transaction do
        rename_table_create_view(table_name, old_new_column_hash)
      end
    end

    # Reverts operations performed by initialize_column_rename
    #
    # @param table_name [String, Symbol] table name
    # @param _column_name [String, Symbol] the name of the column to be renamed.
    #     Passing this argument will make this change reversible in migration
    # @param _new_column_name [String, Symbol] new new name of the column.
    #     Passing this argument will make this change reversible in migration
    #
    # @return [void]
    #
    # @example
    #   revert_initialize_column_rename(:users, :name, :first_name)
    #
    def revert_initialize_column_rename(table_name, _column_name = nil, _new_column_name = nil)
      revert_initialize_columns_rename(table_name, { _column_name => _new_column_name })
    end

    # Same as `revert_initialize_column_rename` but for multiple columns.
    #
    # @param table_name [String, Symbol] table name
    # @param _old_new_column_hash [Hash] the hash of old and new columns
    #     Passing this argument will make this change reversible in migration
    #
    # @return [void]
    #
    # @example
    #   revert_initialize_columns_rename(:users, {fname: :first_name, lname: :last_name})
    #
    def revert_initialize_columns_rename(table_name, _old_new_column_hash = nil)
      transaction do
        execute("DROP VIEW #{quote_table_name(table_name)}")
        rename_table("#{table_name}_column_rename", table_name)
      end
    end

    # Finishes the process of column rename
    #
    # @param (see #initialize_column_rename)
    # @return [void]
    #
    # @example
    #   finalize_column_rename(:users, :name, :first_name)
    #
    def finalize_column_rename(table_name, column_name, new_column_name)
      finalize_columns_rename(table_name, { column_name => new_column_name })
    end

    # Same as `finalize_column_rename` but for multiple columns.
    #
    # @param (see #initialize_columns_rename)
    # @return [void]
    #
    # @example
    #   finalize_columns_rename(:users, {fname: :first_name, lname: :last_name})
    #
    def finalize_columns_rename(table_name, old_new_column_hash)
      transaction do
        execute("DROP VIEW #{quote_table_name(table_name)}")
        rename_table("#{table_name}_column_rename", table_name)
        old_new_column_hash.each_key do |old|
          rename_column(table_name, old, old_new_column_hash[old])
        end
      end
    end

    # Reverts operations performed by finalize_column_rename
    #
    # @param (see #initialize_column_rename)
    # @return [void]
    #
    # @example
    #   revert_finalize_column_rename(:users, :name, :first_name)
    #
    def revert_finalize_column_rename(table_name, column_name, new_column_name)
      revert_finalize_columns_rename(table_name, { column_name => new_column_name })
    end

    # Same as `revert_finalize_column_rename` but for multiple columns.
    #
    # @param (see #initialize_columns_rename)
    # @return [void]
    #
    # @example
    #   revert_finalize_columns_rename(:users, {fname: :first_name, lname: :last_name})
    #
    def revert_finalize_columns_rename(table_name, old_new_column_hash)
      transaction do
        old_new_column_hash.each_key do |old|
          rename_column(table_name, old_new_column_hash[old], old)
        end
        rename_table_create_view(table_name, old_new_column_hash)
      end
    end

    # Renames a table without requiring downtime
    #
    # The technique is built on top of database views, using the following steps:
    #   1. Rename the database table
    #   2. Create a database view using the old table name by pointing to the new table name
    #   3. Add a workaround for ActiveRecord's schema cache
    #
    # For example, to rename `clients` table name to `users`, we can run:
    #
    #     BEGIN;
    #     ALTER TABLE clients RENAME TO users;
    #     CREATE VIEW clients AS SELECT * FROM users;
    #     COMMIT;
    #
    # As database views do not expose the underlying table schema (default values, not null constraints,
    # indexes, etc), further steps are needed to update the application to use the new table name.
    # ActiveRecord heavily relies on this data, for example, to initialize new models.
    #
    # To work around this limitation, we need to tell ActiveRecord to acquire this information
    # from original table using the new table name (see notes).
    #
    # @param table_name [String, Symbol]
    # @param new_name [String, Symbol] table's new name
    #
    # @return [void]
    #
    # @example
    #   initialize_table_rename(:clients, :users)
    #
    # @note
    #   Prior to using this method, you need to register the database table so that
    #   it instructs ActiveRecord to fetch the database table information (for SchemaCache)
    #   using the new table name (if it's present). Otherwise, fall back to the old table name:
    #
    #   ```
    #     OnlineMigrations.config.table_renames[old_table_name] = new_table_name
    #   ```
    #
    #   Deploy this change before proceeding with this helper.
    #   This is necessary to avoid errors during a zero-downtime deployment.
    #
    # @note None of the DDL operations involving original table name can be performed
    #   until `finalize_table_rename` is run
    #
    def initialize_table_rename(table_name, new_name)
      transaction do
        rename_table(table_name, new_name)
        execute("CREATE VIEW #{quote_table_name(table_name)} AS SELECT * FROM #{quote_table_name(new_name)}")
      end
    end

    # Reverts operations performed by initialize_table_rename
    #
    # @param (see #initialize_table_rename)
    # @return [void]
    #
    # @example
    #   revert_initialize_table_rename(:clients, :users)
    #
    def revert_initialize_table_rename(table_name, new_name)
      transaction do
        execute("DROP VIEW IF EXISTS #{quote_table_name(table_name)}")
        rename_table(new_name, table_name)
      end
    end

    # Finishes the process of table rename
    #
    # @param table_name [String, Symbol]
    # @param _new_name [String, Symbol] table's new name. Passing this argument will make
    #   this change reversible in migration
    # @return [void]
    #
    # @example
    #   finalize_table_rename(:users, :clients)
    #
    def finalize_table_rename(table_name, _new_name = nil)
      execute("DROP VIEW IF EXISTS #{quote_table_name(table_name)}")
    end

    # Reverts operations performed by finalize_table_rename
    #
    # @param table_name [String, Symbol]
    # @param new_name [String, Symbol] table's new name
    # @return [void]
    #
    # @example
    #   revert_finalize_table_rename(:users, :clients)
    #
    def revert_finalize_table_rename(table_name, new_name)
      execute("CREATE VIEW #{quote_table_name(table_name)} AS SELECT * FROM #{quote_table_name(new_name)}")
    end

    # Swaps two column names in a table
    #
    # This method is mostly intended for use as one of the steps for
    # concurrent column type change
    #
    # @param table_name [String, Symbol]
    # @param column1 [String, Symbol]
    # @param column2 [String, Symbol]
    # @return [void]
    #
    # @example
    #   swap_column_names(:files, :size_for_type_change, :size)
    #
    def swap_column_names(table_name, column1, column2)
      transaction do
        rename_column(table_name, column1, "#{column1}_tmp")
        rename_column(table_name, column2, column1)
        rename_column(table_name, "#{column1}_tmp", column2)
      end
    end

    # Adds a column with a default value without durable locks of the entire table
    #
    # This method runs the following steps:
    #
    # 1. Add the column allowing NULLs
    # 2. Change the default value of the column to the specified value
    # 3. Backfill all existing rows in batches
    # 4. Set a `NOT NULL` constraint on the column if desired (the default).
    #
    # These steps ensure a column can be added to a large and commonly used table
    # without locking the entire table for the duration of the table modification.
    #
    # For large tables (10/100s of millions of records) you may consider implementing
    #   the steps from this helper method yourself as a separate migrations, replacing step #3
    #   with the help of background migrations (see `backfill_column_in_background`).
    #
    # @param table_name [String, Symbol]
    # @param column_name [String, Symbol]
    # @param type [Symbol] type of new column
    #
    # @param options [Hash] `:batch_size`, `:batch_column_name`, `:progress`, and `:pause_ms`
    #     are directly passed to `update_column_in_batches` to control the backfilling process.
    #     Additional options (like `:limit`, etc) are forwarded to `add_column`
    # @option options :default The column's default value
    # @option options [Boolean] :null (true) Allows or disallows NULL values in the column
    #
    # @return [void]
    #
    # @example
    #   add_column_with_default(:users, :admin, :boolean, default: false, null: false)
    #
    # @example Additional column options
    #   add_column_with_default(:users, :twitter, :string, default: "", limit: 64)
    #
    # @example Additional batching options
    #   add_column_with_default(:users, :admin, :boolean, default: false,
    #                           batch_size: 10_000, pause_ms: 100)
    #
    # @note This method should not be run within a transaction
    # @note For PostgreSQL 11+ you can use `add_column` instead
    #
    def add_column_with_default(table_name, column_name, type, **options)
      default = options.fetch(:default)
      if default.is_a?(Proc) && Utils.ar_version < 5.0 # https://github.com/rails/rails/pull/20005
        raise ArgumentError, "Expressions as default are not supported"
      end

      if raw_connection.server_version >= 11_00_00 && !Utils.volatile_default?(self, type, default)
        add_column(table_name, column_name, type, **options)
      else
        __ensure_not_in_transaction!

        batch_options = options.extract!(:batch_size, :batch_column_name, :progress, :pause_ms)

        if column_exists?(table_name, column_name)
          Utils.say("Column was not created because it already exists (this may be due to an aborted migration " \
                    "or similar) table_name: #{table_name}, column_name: #{column_name}")
        else
          transaction do
            add_column(table_name, column_name, type, **options.merge(default: nil, null: true))
            change_column_default(table_name, column_name, default)
          end
        end

        update_column_in_batches(table_name, column_name, default, **batch_options)

        allow_null = options.delete(:null) != false
        if !allow_null
          # A `NOT NULL` constraint for the column is functionally equivalent
          # to creating a CHECK constraint `CHECK (column IS NOT NULL)` for the table
          add_not_null_constraint(table_name, column_name, validate: false)
          validate_not_null_constraint(table_name, column_name)

          if raw_connection.server_version >= 12_00_00
            # In PostgreSQL 12+ it is safe to "promote" a CHECK constraint to `NOT NULL` for the column
            change_column_null(table_name, column_name, false)
            remove_not_null_constraint(table_name, column_name)
          end
        end
      end
    end

    # Adds a NOT NULL constraint to the column
    #
    # @param table_name [String, Symbol]
    # @param column_name [String, Symbol]
    # @param name [String, Symbol] the constraint name.
    #     Defaults to `chk_rails_<identifier>`
    # @param validate [Boolean] whether or not the constraint should be validated
    #
    # @return [void]
    #
    # @example
    #   add_not_null_constraint(:users, :email, validate: false)
    #
    def add_not_null_constraint(table_name, column_name, name: nil, validate: true)
      if __column_not_nullable?(table_name, column_name) ||
         __not_null_constraint_exists?(table_name, column_name, name: name)
        Utils.say("NOT NULL constraint was not created: column #{table_name}.#{column_name} is already defined as `NOT NULL`")
      else
        expression = "#{column_name} IS NOT NULL"
        name ||= __not_null_constraint_name(table_name, column_name)
        add_check_constraint(table_name, expression, name: name, validate: false)

        if validate
          validate_not_null_constraint(table_name, column_name, name: name)
        end
      end
    end

    # Validates a NOT NULL constraint on the column
    #
    # @param table_name [String, Symbol]
    # @param column_name [String, Symbol]
    # @param name [String, Symbol] the constraint name.
    #     Defaults to `chk_rails_<identifier>`
    #
    # @return [void]
    #
    # @example
    #   validate_not_null_constraint(:users, :email)
    #
    # @example Explicit name
    #   validate_not_null_constraint(:users, :email, name: "check_users_email_null")
    #
    def validate_not_null_constraint(table_name, column_name, name: nil)
      name ||= __not_null_constraint_name(table_name, column_name)
      validate_check_constraint(table_name, name: name)
    end

    # Removes a NOT NULL constraint from the column
    #
    # @param table_name [String, Symbol]
    # @param column_name [String, Symbol]
    # @param name [String, Symbol] the constraint name.
    #     Defaults to `chk_rails_<identifier>`
    #
    # @return [void]
    #
    # @example
    #   remove_not_null_constraint(:users, :email)
    #
    # @example Explicit name
    #   remove_not_null_constraint(:users, :email, name: "check_users_email_null")
    #
    def remove_not_null_constraint(table_name, column_name, name: nil)
      name ||= __not_null_constraint_name(table_name, column_name)
      remove_check_constraint(table_name, name: name)
    end

    # Adds a limit constraint to the text column
    #
    # @param table_name [String, Symbol]
    # @param column_name [String, Symbol]
    # @param name [String, Symbol] the constraint name.
    #     Defaults to `chk_rails_<identifier>`
    # @param validate [Boolean] whether or not the constraint should be validated
    #
    # @return [void]
    #
    # @example
    #   add_text_limit_constraint(:users, :bio, 255)
    #
    # @note This helper must be used only with text columns
    #
    def add_text_limit_constraint(table_name, column_name, limit, name: nil, validate: true)
      column = __column_for(table_name, column_name)
      if column.type != :text
        raise "add_text_limit_constraint must be used only with :text columns"
      end

      name ||= __text_limit_constraint_name(table_name, column_name)

      if __text_limit_constraint_exists?(table_name, column_name, name: name)
        Utils.say("Text limit constraint was not created: #{table_name}.#{column_name} is already has a limit")
      else
        add_check_constraint(
          table_name,
          "char_length(#{column_name}) <= #{limit}",
          name: name,
          validate: false
        )

        if validate
          validate_text_limit_constraint(table_name, column_name, name: name)
        end
      end
    end

    # Validates a limit constraint on the text column
    #
    # @param table_name [String, Symbol]
    # @param column_name [String, Symbol]
    # @param name [String, Symbol] the constraint name.
    #     Defaults to `chk_rails_<identifier>`
    #
    # @return [void]
    #
    # @example
    #   validate_text_limit_constraint(:users, :bio)
    #
    # @example Explicit name
    #   validate_text_limit_constraint(:users, :bio, name: "check_users_bio_max_length")
    #
    def validate_text_limit_constraint(table_name, column_name, name: nil)
      name ||= __text_limit_constraint_name(table_name, column_name)
      validate_check_constraint(table_name, name: name)
    end

    # Removes a limit constraint from the text column
    #
    # @param table_name [String, Symbol]
    # @param column_name [String, Symbol]
    # @param name [String, Symbol] the constraint name.
    #     Defaults to `chk_rails_<identifier>`
    #
    # @return [void]
    #
    # @example
    #   remove_text_limit_constraint(:users, :bio)
    #
    # @example Explicit name
    #   remove_not_null_constraint(:users, :bio, name: "check_users_bio_max_length")
    #
    def remove_text_limit_constraint(table_name, column_name, _limit = nil, name: nil)
      name ||= __text_limit_constraint_name(table_name, column_name)
      remove_check_constraint(table_name, name: name)
    end

    # Adds a reference to the table with minimal locking
    #
    # ActiveRecord adds an index non-`CONCURRENTLY` to references by default, which blocks writes.
    # It also adds a validated foreign key by default, which blocks writes on both tables while
    # validating existing rows.
    #
    # This method makes sure that an index is added `CONCURRENTLY` and the foreign key creation is performed
    # in 2 steps: addition of invalid foreign key and a separate validation.
    #
    # @param table_name [String, Symbol] table name
    # @param ref_name [String, Symbol] new column name
    # @param options [Hash] look at
    #   https://edgeapi.rubyonrails.org/classes/ActiveRecord/ConnectionAdapters/SchemaStatements.html#method-i-add_reference for available options
    #
    # @return [void]
    #
    # @example
    #   add_reference_concurrently(:projects, :user)
    #
    # @note This method should not be run within a transaction
    #
    def add_reference_concurrently(table_name, ref_name, **options)
      __ensure_not_in_transaction!

      column_name = "#{ref_name}_id"
      unless column_exists?(table_name, column_name)
        type = options[:type] || (Utils.ar_version >= 5.1 ? :bigint : :integer)
        allow_null = options.fetch(:null, true)
        add_column(table_name, column_name, type, null: allow_null)
      end

      # Always added by default in 5.0+
      index = options.fetch(:index) { Utils.ar_version >= 5.0 }

      if index
        index = {} if index == true
        index_columns = [column_name]
        if options[:polymorphic]
          index[:name] ||= "index_#{table_name}_on_#{ref_name}"
          index_columns.unshift("#{ref_name}_type")
        end

        add_index(table_name, index_columns, **index.merge(algorithm: :concurrently))
      end

      foreign_key = options[:foreign_key]

      if foreign_key
        foreign_key = {} if foreign_key == true

        foreign_table_name = Utils.foreign_table_name(ref_name, foreign_key)
        add_foreign_key(table_name, foreign_table_name, **foreign_key.merge(validate: false))

        if foreign_key[:validate] != false
          validate_foreign_key(table_name, foreign_table_name, **foreign_key)
        end
      end
    end

    # Extends default method to be idempotent and automatically recreate invalid indexes.
    #
    # @see https://edgeapi.rubyonrails.org/classes/ActiveRecord/ConnectionAdapters/SchemaStatements.html#method-i-add_index
    #
    def add_index(table_name, column_name, options = {})
      algorithm = options[:algorithm]

      __ensure_not_in_transaction! if algorithm == :concurrently

      column_names = __index_column_names(column_name || options[:column])

      index_name = options[:name]
      index_name ||= index_name(table_name, column_names)

      if index_exists?(table_name, column_name, **options)
        schema = __schema_for_table(table_name)

        if __index_valid?(index_name, schema: schema)
          Utils.say("Index was not created because it already exists (this may be due to an aborted migration " \
                    "or similar): table_name: #{table_name}, column_name: #{column_name}")
          return
        else
          Utils.say("Recreating invalid index: table_name: #{table_name}, column_name: #{column_name}")
          remove_index(table_name, column_name, name: index_name, algorithm: algorithm)
        end
      end

      disable_statement_timeout do
        # "CREATE INDEX CONCURRENTLY" requires a "SHARE UPDATE EXCLUSIVE" lock.
        # It only conflicts with constraint validations, creating/removing indexes,
        # and some other "ALTER TABLE"s.
        super(table_name, column_name, **options.merge(name: index_name))
      end
    end

    # Extends default method to be idempotent and accept `:algorithm` option for ActiveRecord <= 4.2.
    #
    # @see https://edgeapi.rubyonrails.org/classes/ActiveRecord/ConnectionAdapters/SchemaStatements.html#method-i-remove_index
    #
    def remove_index(table_name, column_name = nil, **options)
      algorithm = options[:algorithm]

      __ensure_not_in_transaction! if algorithm == :concurrently

      column_names = __index_column_names(column_name || options[:column])
      index_name = options[:name]
      index_name ||= index_name(table_name, column_names)

      index_exists =
        if Utils.ar_version <= 5.0
          # Older Active Record is unable to handle blank columns correctly in `index_exists?`,
          # so we need to use `index_name_exists?`.
          index_name_exists?(table_name, index_name, nil)
        elsif Utils.ar_version <= 6.0
          index_name_exists?(table_name, index_name)
        else
          index_exists?(table_name, column_names, **options)
        end

      if index_exists
        disable_statement_timeout do
          # "DROP INDEX CONCURRENTLY" requires a "SHARE UPDATE EXCLUSIVE" lock.
          # It only conflicts with constraint validations, other creating/removing indexes,
          # and some "ALTER TABLE"s.

          # ActiveRecord <= 4.2 does not support removing indexes concurrently
          if Utils.ar_version <= 4.2 && algorithm == :concurrently
            execute("DROP INDEX CONCURRENTLY #{quote_table_name(index_name)}")
          else
            super(table_name, **options.merge(column: column_names))
          end
        end
      else
        Utils.say("Index was not removed because it does not exist (this may be due to an aborted migration " \
                  "or similar): table_name: #{table_name}, column_name: #{column_names}")
      end
    end

    # Extends default method to be idempotent and accept `:validate` option for ActiveRecord < 5.2.
    #
    # @see https://edgeapi.rubyonrails.org/classes/ActiveRecord/ConnectionAdapters/SchemaStatements.html#method-i-add_foreign_key
    #
    def add_foreign_key(from_table, to_table, validate: true, **options)
      if foreign_key_exists?(from_table, to_table, **options)
        message = "Foreign key was not created because it already exists " \
                  "(this can be due to an aborted migration or similar): from_table: #{from_table}, to_table: #{to_table}".dup
        message << ", #{options.inspect}" if options.any?

        Utils.say(message)
      else
        # ActiveRecord >= 5.2 supports adding non-validated foreign keys natively
        options = options.dup
        options[:column] ||= "#{to_table.to_s.singularize}_id"
        options[:primary_key] ||= "id"
        options[:name] ||= __foreign_key_name(to_table, options[:column])

        query = <<-SQL.strip_heredoc.dup
          ALTER TABLE #{quote_table_name(from_table)}
          ADD CONSTRAINT #{quote_column_name(options[:name])}
          FOREIGN KEY (#{quote_column_name(options[:column])})
          REFERENCES #{quote_table_name(to_table)} (#{quote_column_name(options[:primary_key])})
        SQL
        query << "#{__action_sql('DELETE', options[:on_delete])}\n" if options[:on_delete].present?
        query << "#{__action_sql('UPDATE', options[:on_update])}\n" if options[:on_update].present?
        query << "NOT VALID\n" if !validate
        if Utils.ar_version >= 7.0 && options[:deferrable]
          query << " DEFERRABLE"
          query << " INITIALLY #{options[:deferrable].to_s.upcase}\n" if options[:deferrable] != true
        end

        execute(query.squish)
      end
    end

    # Extends default method with disabled statement timeout while validation is run
    #
    # @see https://edgeapi.rubyonrails.org/classes/ActiveRecord/ConnectionAdapters/PostgreSQL/SchemaStatements.html#method-i-validate_foreign_key
    # @note This method was added in ActiveRecord 5.2
    #
    def validate_foreign_key(from_table, to_table = nil, **options)
      fk_name_to_validate = __foreign_key_for!(from_table, to_table: to_table, **options).name

      # Skip costly operation if already validated.
      return if __constraint_validated?(from_table, fk_name_to_validate, type: :foreign_key)

      disable_statement_timeout do
        # "VALIDATE CONSTRAINT" requires a "SHARE UPDATE EXCLUSIVE" lock.
        # It only conflicts with other validations, creating/removing indexes,
        # and some other "ALTER TABLE"s.
        execute("ALTER TABLE #{quote_table_name(from_table)} VALIDATE CONSTRAINT #{quote_column_name(fk_name_to_validate)}")
      end
    end

    def foreign_key_exists?(from_table, to_table = nil, **options)
      foreign_keys(from_table).any? { |fk| fk.defined_for?(to_table: to_table, **options) }
    end

    # Extends default method to be idempotent
    #
    # @see https://edgeapi.rubyonrails.org/classes/ActiveRecord/ConnectionAdapters/SchemaStatements.html#method-i-add_check_constraint
    # @note This method was added in ActiveRecord 6.1
    #
    def add_check_constraint(table_name, expression, validate: true, **options)
      constraint_name = __check_constraint_name(table_name, expression: expression, **options)

      if __check_constraint_exists?(table_name, constraint_name)
        Utils.say("Check constraint was not created because it already exists (this may be due to an aborted migration " \
                  "or similar) table_name: #{table_name}, expression: #{expression}, constraint name: #{constraint_name}")
      else
        query = <<-SQL.squish
          ALTER TABLE #{quote_table_name(table_name)}
            ADD CONSTRAINT #{quote_column_name(constraint_name)} CHECK (#{expression})
        SQL
        query += " NOT VALID" if !validate

        execute(query)
      end
    end

    # Extends default method with disabled statement timeout while validation is run
    #
    # @see https://edgeapi.rubyonrails.org/classes/ActiveRecord/ConnectionAdapters/PostgreSQL/SchemaStatements.html#method-i-validate_check_constraint
    # @note This method was added in ActiveRecord 6.1
    #
    def validate_check_constraint(table_name, **options)
      constraint_name = __check_constraint_name!(table_name, **options)

      # Skip costly operation if already validated.
      return if __constraint_validated?(table_name, constraint_name, type: :check)

      disable_statement_timeout do
        # "VALIDATE CONSTRAINT" requires a "SHARE UPDATE EXCLUSIVE" lock.
        # It only conflicts with other validations, creating/removing indexes,
        # and some other "ALTER TABLE"s.
        execute(<<-SQL.squish)
          ALTER TABLE #{quote_table_name(table_name)}
            VALIDATE CONSTRAINT #{quote_column_name(constraint_name)}
        SQL
      end
    end

    if Utils.ar_version < 6.1
      # @see https://edgeapi.rubyonrails.org/classes/ActiveRecord/ConnectionAdapters/SchemaStatements.html#method-i-remove_check_constraint
      # @note This method was added in ActiveRecord 6.1
      #
      def remove_check_constraint(table_name, expression = nil, **options)
        constraint_name = __check_constraint_name!(table_name, expression: expression, **options)
        execute(<<-SQL.squish)
          ALTER TABLE #{quote_table_name(table_name)}
            DROP CONSTRAINT #{quote_column_name(constraint_name)}
        SQL
      end
    end

    if Utils.ar_version <= 4.2
      # @private
      def views
        select_values(<<-SQL, "SCHEMA")
          SELECT c.relname
          FROM pg_class c
          LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE c.relkind IN ('v','m') -- (v)iew, (m)aterialized view
          AND n.nspname = ANY (current_schemas(false))
        SQL
      end
    end

    # @private
    def pk_and_sequence_for(table)
      views = self.views

      table_renames = OnlineMigrations.config.table_renames
      renamed_tables = table_renames.select do |old_name, _|
        views.include?(old_name)
      end

      column_renames = OnlineMigrations.config.column_renames
      renamed_columns = column_renames.select do |table_name, _|
        views.include?(table_name)
      end

      if renamed_tables.key?(table)
        super(renamed_tables[table])
      elsif renamed_columns.key?(table)
        super("#{table}_column_rename")
      else
        super
      end
    end

    # Disables statement timeout while executing &block
    #
    # Long-running migrations may take more than the timeout allowed by the database.
    # Disable the session's statement timeout to ensure migrations don't get killed prematurely.
    #
    # Statement timeouts are already disabled in `add_index`, `remove_index`,
    # `validate_foreign_key`, and `validate_check_constraint` helpers.
    #
    # @return [void]
    #
    # @example
    #   disable_statement_timeout do
    #     add_index(:users, :email, unique: true, algorithm: :concurrently)
    #   end
    #
    def disable_statement_timeout
      prev_value = select_value("SHOW statement_timeout")
      execute("SET statement_timeout TO 0")

      yield
    ensure
      execute("SET statement_timeout TO #{quote(prev_value)}")
    end

    # @private
    # Executes the block with a retry mechanism that alters the `lock_timeout`
    # and sleep time between attempts.
    #
    def with_lock_retries(&block)
      __ensure_not_in_transaction!

      retrier = OnlineMigrations.config.lock_retrier
      retrier.connection = self
      retrier.with_lock_retries(&block)
    end

    private
      # Private methods are prefixed with `__` to avoid clashes with existing or future
      # ActiveRecord methods
      def __ensure_not_in_transaction!(method_name = caller[0])
        if transaction_open?
          raise <<-MSG.strip_heredoc
            `#{method_name}` cannot run inside a transaction block.

            You can remove transaction block by calling `disable_ddl_transaction!` in the body of
            your migration class.
          MSG
        end
      end

      def __column_not_nullable?(table_name, column_name)
        schema = __schema_for_table(table_name)

        query = <<-SQL.strip_heredoc
          SELECT is_nullable
          FROM information_schema.columns
          WHERE table_schema = #{schema}
            AND table_name = #{quote(table_name)}
            AND column_name = #{quote(column_name)}
        SQL

        select_value(query) == "NO"
      end

      def __not_null_constraint_exists?(table_name, column_name, name: nil)
        name ||= __not_null_constraint_name(table_name, column_name)
        __check_constraint_exists?(table_name, name)
      end

      def __not_null_constraint_name(table_name, column_name)
        __check_constraint_name(table_name, expression: "#{column_name}_not_null")
      end

      def __text_limit_constraint_name(table_name, column_name)
        __check_constraint_name(table_name, expression: "#{column_name}_max_length")
      end

      def __text_limit_constraint_exists?(table_name, column_name, name: nil)
        name ||= __text_limit_constraint_name(table_name, column_name)
        __check_constraint_exists?(table_name, name)
      end

      def __index_column_names(column_names)
        if column_names.is_a?(String) && /\W/.match(column_names)
          column_names
        elsif column_names.present?
          Array(column_names)
        end
      end

      def __index_valid?(index_name, schema:)
        # ActiveRecord <= 4.2 returns a string, instead of automatically casting to boolean
        valid = select_value <<-SQL.strip_heredoc
          SELECT indisvalid
          FROM pg_index i
          JOIN pg_class c
            ON i.indexrelid = c.oid
          JOIN pg_namespace n
            ON c.relnamespace = n.oid
          WHERE n.nspname = #{schema}
            AND c.relname = #{quote(index_name)}
        SQL

        Utils.to_bool(valid)
      end

      def __column_for(table_name, column_name)
        column_name = column_name.to_s

        columns(table_name).find { |c| c.name == column_name } ||
          raise("No such column: #{table_name}.#{column_name}")
      end

      def __action_sql(action, dependency)
        case dependency
        when :nullify then "ON #{action} SET NULL"
        when :cascade  then "ON #{action} CASCADE"
        when :restrict then "ON #{action} RESTRICT"
        else
          raise ArgumentError, <<-MSG.strip_heredoc
            '#{dependency}' is not supported for :on_update or :on_delete.
            Supported values are: :nullify, :cascade, :restrict
          MSG
        end
      end

      def __copy_foreign_key(fk, to_column, **options)
        fkey_options = {
          column: to_column,
          primary_key: options[:primary_key] || fk.primary_key,
          on_delete: fk.on_delete,
          on_update: fk.on_update,
          validate: false,
        }
        fkey_options[:name] = options[:name] if options[:name]

        add_foreign_key(
          fk.from_table,
          fk.to_table,
          **fkey_options
        )

        if !fk.respond_to?(:validated?) || fk.validated?
          validate_foreign_key(fk.from_table, fk.to_table, column: to_column, **options)
        end
      end

      def __foreign_key_name(table_name, column_name)
        identifier = "#{table_name}_#{column_name}_fk"
        hashed_identifier = Digest::SHA256.hexdigest(identifier).first(10)

        "fk_rails_#{hashed_identifier}"
      end

      if Utils.ar_version <= 4.2
        def foreign_key_for(from_table, **options)
          foreign_keys(from_table).detect { |fk| fk.defined_for?(**options) }
        end
      end

      def __foreign_key_for!(from_table, **options)
        foreign_key_for(from_table, **options) ||
          raise(ArgumentError, "Table '#{from_table}' has no foreign key for #{options[:to_table] || options}")
      end

      def __constraint_validated?(table_name, name, type:)
        schema = __schema_for_table(table_name)
        contype = type == :check ? "c" : "f"

        validated = select_value(<<-SQL.strip_heredoc)
          SELECT convalidated
          FROM pg_catalog.pg_constraint con
            INNER JOIN pg_catalog.pg_namespace nsp
              ON nsp.oid = con.connamespace
          WHERE con.conrelid = #{quote(table_name)}::regclass
            AND con.conname = #{quote(name)}
            AND con.contype = '#{contype}'
            AND nsp.nspname = #{schema}
        SQL

        Utils.to_bool(validated)
      end

      def __check_constraint_name!(table_name, expression: nil, **options)
        constraint_name = __check_constraint_name(table_name, expression: expression, **options)

        if __check_constraint_exists?(table_name, constraint_name)
          constraint_name
        else
          raise(ArgumentError, "Table '#{table_name}' has no check constraint for #{expression || options}")
        end
      end

      def __check_constraint_name(table_name, **options)
        options.fetch(:name) do
          expression = options.fetch(:expression)
          identifier = "#{table_name}_#{expression}_chk"
          hashed_identifier = Digest::SHA256.hexdigest(identifier).first(10)

          "chk_rails_#{hashed_identifier}"
        end
      end

      def __check_constraint_exists?(table_name, constraint_name)
        schema = __schema_for_table(table_name)

        check_sql = <<-SQL.strip_heredoc
          SELECT COUNT(*)
          FROM pg_catalog.pg_constraint con
            INNER JOIN pg_catalog.pg_class cl
              ON cl.oid = con.conrelid
            INNER JOIN pg_catalog.pg_namespace nsp
              ON nsp.oid = con.connamespace
          WHERE con.contype = 'c'
            AND con.conname = #{quote(constraint_name)}
            AND cl.relname = #{quote(table_name)}
            AND nsp.nspname = #{schema}
        SQL

        select_value(check_sql).to_i > 0
      end

      def __schema_for_table(table_name)
        _, schema = table_name.to_s.split(".").reverse
        schema ? quote(schema) : "current_schema()"
      end

      def rename_table_create_view(table_name, old_new_column_hash)
        tmp_table = "#{table_name}_column_rename"
        rename_table(table_name, tmp_table)
        column_mapping = old_new_column_hash.keys.map do |old|
          "#{quote_column_name(old)} AS #{quote_column_name(old_new_column_hash[old])}"
        end.join(", ")
        execute(<<-SQL.squish)
          CREATE VIEW #{quote_table_name(table_name)} AS
            SELECT *, #{column_mapping}
            FROM #{quote_table_name(tmp_table)}
        SQL
      end
  end
end
