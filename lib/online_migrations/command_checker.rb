# frozen_string_literal: true

require "erb"
require "set"

module OnlineMigrations
  # @private
  class CommandChecker
    class << self
      attr_accessor :safe

      def safety_assured
        prev_value = safe
        self.safe = true
        yield
      ensure
        self.safe = prev_value
      end
    end

    attr_accessor :direction

    def initialize(migration)
      @migration = migration
      @new_tables = []
      @new_columns = []
      @lock_timeout_checked = false
      @foreign_key_tables = Set.new
      @removed_indexes = []
    end

    def check(command, *args, &block)
      check_database_version
      set_statement_timeout
      check_lock_timeout

      if !safe?
        do_check(command, *args, &block)

        run_custom_checks(command, args)

        if @foreign_key_tables.count { |t| !new_table?(t) } > 1
          raise_error :multiple_foreign_keys
        end
      end

      true
    end
    ruby2_keywords(:check) if respond_to?(:ruby2_keywords, true)

    def version_safe?
      version && version <= OnlineMigrations.config.start_after
    end

    private
      ERROR_MESSAGE_TO_LINK = {
        multiple_foreign_keys: "adding-multiple-foreign-keys",
        create_table: "creating-a-table-with-the-force-option",
        short_primary_key_type: "using-primary-key-with-short-integer-type",
        drop_table_multiple_foreign_keys: "removing-a-table-with-multiple-foreign-keys",
        rename_table: "renaming-a-table",
        add_column_with_default_null: "adding-a-column-with-a-default-value",
        add_column_with_default: "adding-a-column-with-a-default-value",
        add_column_generated_stored: "adding-a-stored-generated-column",
        add_column_json: "adding-a-json-column",
        rename_column: "renaming-a-column",
        change_column: "changing-the-type-of-a-column",
        change_column_default: "changing-the-default-value-of-a-column",
        change_column_null: "setting-not-null-on-an-existing-column",
        remove_column: "removing-a-column",
        add_timestamps_with_default: "adding-a-column-with-a-default-value",
        add_hash_index: "hash-indexes",
        add_reference: "adding-a-reference",
        add_index: "adding-an-index-non-concurrently",
        replace_index: "replacing-an-index",
        remove_index: "removing-an-index-non-concurrently",
        add_foreign_key: "adding-a-foreign-key",
        add_exclusion_constraint: "adding-an-exclusion-constraint",
        add_check_constraint: "adding-a-check-constraint",
        add_unique_constraint: "adding-a-unique-constraint",
        execute: "executing-SQL-directly",
        add_inheritance_column: "adding-a-single-table-inheritance-column",
        mismatched_foreign_key_type: "mismatched-reference-column-types",
      }

      def check_database_version
        return if defined?(@database_version_checked)

        adapter = connection.adapter_name
        case adapter
        when /postg/i
          if postgresql_version < Gem::Version.new("9.6")
            raise "#{adapter} < 9.6 is not supported"
          end
        else
          raise "#{adapter} is not supported"
        end

        @database_version_checked = true
      end

      def set_statement_timeout
        if !@statement_timeout_set
          if (statement_timeout = OnlineMigrations.config.statement_timeout)
            # TODO: inline this method call after deprecated `disable_statement_timeout` method removal.
            connection.__set_statement_timeout(statement_timeout)
          end
          @statement_timeout_set = true
        end
      end

      def check_lock_timeout
        limit = OnlineMigrations.config.lock_timeout_limit

        if limit && !@lock_timeout_checked
          lock_timeout = connection.select_value("SHOW lock_timeout")
          lock_timeout_sec = timeout_to_sec(lock_timeout)

          if lock_timeout_sec == 0
            Utils.warn("DANGER: No lock timeout set")
          elsif lock_timeout_sec > limit
            Utils.warn("DANGER: Lock timeout is longer than #{limit} seconds: #{lock_timeout}")
          end

          @lock_timeout_checked = true
        end
      end

      def timeout_to_sec(timeout)
        units = {
          "us" => 10**-6,
          "ms" => 10**-3,
          "s" => 1,
          "min" => 60,
          "h" => 60 * 60,
          "d" => 60 * 60 * 24,
        }

        timeout_sec = timeout.to_i

        units.each do |k, v|
          if timeout.end_with?(k)
            timeout_sec *= v
            break
          end
        end
        timeout_sec
      end

      def safe?
        self.class.safe ||
          ENV["SAFETY_ASSURED"] ||
          (direction == :down && !OnlineMigrations.config.check_down) ||
          version_safe? ||
          @migration.reverting?
      end

      def version
        @migration.version || @migration.class.version
      end

      def do_check(command, *args, **options, &block)
        case command
        when :remove_column, :remove_columns, :remove_timestamps, :remove_reference, :remove_belongs_to
          check_columns_removal(command, *args, **options)
        else
          if respond_to?(command, true)
            send(command, *args, **options, &block)
          else
            # assume it is safe
            true
          end
        end
      end

      def create_table(table_name, **options, &block)
        raise_error :create_table if options[:force]

        # Probably, it would be good idea to also check for foreign keys
        # with short integer types, and for mismatched primary key vs foreign key types.
        # But I think this check is enough for now.
        raise_error :short_primary_key_type if short_primary_key_type?(options)

        if block
          collect_foreign_keys(&block)
          check_for_hash_indexes(&block) if postgresql_version < Gem::Version.new("10")
        end

        @new_tables << table_name.to_s
      end

      def create_join_table(table1, table2, **options, &block)
        table_name = options[:table_name] || derive_join_table_name(table1, table2)
        create_table(table_name, **options, &block)
      end

      def drop_table(table_name, **_options)
        foreign_keys = connection.foreign_keys(table_name)
        referenced_tables = foreign_keys.map(&:to_table).uniq
        referenced_tables.delete(table_name.to_s) # ignore self references

        if referenced_tables.count { |t| !new_table?(t) } > 1
          raise_error :drop_table_multiple_foreign_keys
        end
      end

      def drop_join_table(table1, table2, **options)
        table_name = options[:table_name] || derive_join_table_name(table1, table2)
        drop_table(table_name, **options)
      end

      def change_table(*)
        raise_error :change_table, header: "Possibly dangerous operation"
      end

      def rename_table(table_name, new_name, **)
        if !new_table?(table_name)
          raise_error :rename_table,
            table_name: table_name,
            new_name: new_name
        end
      end

      def add_column(table_name, column_name, type, **options)
        type = type.to_sym
        default = options[:default]
        volatile_default = false

        # Keep track of new columns for change_column_default check.
        @new_columns << [table_name.to_s, column_name.to_s]

        if !new_or_small_table?(table_name)
          if options.key?(:default) &&
             (postgresql_version < Gem::Version.new("11") || (!default.nil? && (volatile_default = Utils.volatile_default?(connection, type, default))))

            if default.nil?
              raise_error :add_column_with_default_null,
                code: command_str(:add_column, table_name, column_name, type, options.except(:default))
            else
              raise_error :add_column_with_default,
                code: command_str(:add_column_with_default, table_name, column_name, type, options),
                not_null: options[:null] == false,
                volatile_default: volatile_default
            end
          end

          if type == :virtual && options[:stored]
            raise_error :add_column_generated_stored
          end
        end

        if type == :json
          raise_error :add_column_json,
            code: command_str(:add_column, table_name, column_name, :jsonb, options)
        end

        check_inheritance_column(table_name, column_name, default)

        type = :bigint if type == :integer && options[:limit] == 8
        check_mismatched_foreign_key_type(table_name, column_name, type)
      end

      def add_column_with_default(table_name, column_name, type, **options)
        type = type.to_sym

        if type == :json
          raise_error :add_column_json,
            code: command_str(:add_column_with_default, table_name, column_name, :jsonb, options)
        end

        check_inheritance_column(table_name, column_name, options[:default])

        type = :bigint if type == :integer && options[:limit] == 8
        check_mismatched_foreign_key_type(table_name, column_name, type)
      end

      def rename_column(table_name, column_name, new_column, **)
        if !new_table?(table_name)
          raise_error :rename_column,
            table_name: table_name,
            column_name: column_name,
            new_column: new_column,
            model: table_name.to_s.classify,
            partial_writes: Utils.ar_partial_writes?,
            partial_writes_setting: Utils.ar_partial_writes_setting,
            enumerate_columns_in_select_statements: Utils.ar_enumerate_columns_in_select_statements
        end
      end

      def change_column(table_name, column_name, type, **options)
        return if new_table?(table_name)

        type = type.to_sym

        # Ignore internal Active Record migrations compatibility related
        # options, like `_uses_legacy_table_name` etc. They all are starting with "_".
        options = options.reject { |key, _| key.to_s.start_with?("_") }

        existing_column = column_for(table_name, column_name)
        if existing_column
          existing_type = existing_column.type.to_sym

          # To get a list of binary-coercible types:
          #
          # SELECT stype.typname AS source, ttype.typname AS target
          # FROM pg_cast
          #   INNER JOIN pg_type stype ON pg_cast.castsource = stype.oid
          #   INNER JOIN pg_type ttype ON pg_cast.casttarget = ttype.oid
          # WHERE castmethod = 'b'
          # ORDER BY 1, 2

          # https://www.postgresql.org/docs/release/9.2.0/#AEN124164

          safe =
            case type
            when :string
              # safe to increase limit or remove it
              # not safe to decrease limit or add a limit
              case existing_type
              when :string
                !options[:limit] || (existing_column.limit && options[:limit] >= existing_column.limit)
              when :text, :xml
                !options[:limit]
              when :citext
                !options[:limit] && !indexed?(table_name, column_name)
              end
            when :text
              [:string, :text, :xml].include?(existing_type) ||
              (existing_type == :citext && !indexed?(table_name, column_name))
            when :citext
              [:string, :text].include?(existing_type) && !indexed?(table_name, column_name)
            when :bit_varying
              case existing_type
              when :bit
                !options[:limit]
              when :bit_varying
                # safe to increase limit or remove it
                # not safe to decrease limit or add a limit
                !options[:limit] || (existing_column.limit && options[:limit] >= existing_column.limit)
              end
            when :numeric, :decimal
              # numeric and decimal are equivalent and can be used interchangeably
              [:numeric, :decimal].include?(existing_type) &&
              (
                (
                  # unconstrained
                  !options[:precision] && !options[:scale]
                ) || (
                  # increased precision, same scale
                  options[:precision] && existing_column.precision &&
                  options[:precision] >= existing_column.precision &&
                  options[:scale] == existing_column.scale
                )
              )
            when :datetime, :timestamp, :timestamptz
              # precision for datetime
              # limit for timestamp, timestamptz
              precision = (type == :datetime ? options[:precision] : options[:limit]) || 6
              existing_precision = existing_column.precision || existing_column.limit || 6

              [:datetime, :timestamp, :timestamptz].include?(existing_type) &&
              precision >= existing_precision &&
              (type == existing_type ||
                (postgresql_version >= Gem::Version.new("12") &&
                connection.select_value("SHOW timezone") == "UTC"))
            when :interval
              precision = options[:precision] || options[:limit] || 6
              existing_precision = existing_column.precision || existing_column.limit || 6

              existing_type == :interval && precision >= existing_precision
            when :inet
              existing_type == :cidr
            else
              type == existing_type &&
              options[:limit] == existing_column.limit &&
              options[:precision] == existing_column.precision &&
              options[:scale] == existing_column.scale
            end

          # unsafe to set NOT NULL for safe types
          if safe && existing_column.null && options[:null] == false
            raise_error :change_column_with_not_null
          end

          if !safe
            raise_error :change_column,
              initialize_change_code: command_str(:initialize_column_type_change, table_name, column_name, type, **options),
              backfill_code: command_str(:backfill_column_for_type_change, table_name, column_name, **options),
              finalize_code: command_str(:finalize_column_type_change, table_name, column_name),
              cleanup_code: command_str(:cleanup_column_type_change, table_name, column_name),
              cleanup_down_code: command_str(:initialize_column_type_change, table_name, column_name, existing_type)
          end
        end
      end

      def change_column_default(table_name, column_name, _default_or_changes)
        if Utils.ar_partial_writes? && !new_column?(table_name, column_name)
          raise_error :change_column_default,
            config: Utils.ar_partial_writes_setting
        end
      end

      def change_column_null(table_name, column_name, allow_null, default = nil, **)
        if !allow_null && !new_or_small_table?(table_name)
          safe = false
          # In PostgreSQL 12+ you can add a check constraint to the table
          # and then "promote" it to NOT NULL for the column.
          if postgresql_version >= Gem::Version.new("12")
            safe = check_constraints(table_name).any? do |c|
              c["def"] == "CHECK ((#{column_name} IS NOT NULL))" ||
                c["def"] == "CHECK ((#{connection.quote_column_name(column_name)} IS NOT NULL))"
            end
          end

          if !safe
            constraint_name = "#{table_name}_#{column_name}_null"
            vars = {
              add_constraint_code: command_str(:add_not_null_constraint, table_name, column_name, name: constraint_name, validate: false),
              validate_constraint_code: command_str(:validate_not_null_constraint, table_name, column_name, name: constraint_name),
              remove_constraint_code: nil,
              table_name: table_name,
              column_name: column_name,
              default: default,
            }

            if postgresql_version >= Gem::Version.new("12")
              vars[:remove_constraint_code] = command_str(:remove_check_constraint, table_name, name: constraint_name)
              vars[:change_column_null_code] = command_str(:change_column_null, table_name, column_name, false)
            end

            raise_error :change_column_null, **vars
          end
        end
      end

      def check_columns_removal(command, *args, **options)
        case command
        when :remove_column
          table_name, column_name = args
          columns = [column_name]
        when :remove_columns
          table_name, *columns = args
        when :remove_timestamps
          table_name = args[0]
          columns = ["created_at", "updated_at"]
        else
          table_name, reference = args
          columns = ["#{reference}_id"]
          columns << "#{reference}_type" if options[:polymorphic]
        end

        columns = columns.map(&:to_s)

        if !new_table?(table_name)
          indexes = connection.indexes(table_name).select do |index|
            case index.columns
            when String
              # Expression index
              columns.any? { |column| index.columns.include?(column) }
            else
              (index.columns & columns).any?
            end
          end

          raise_error :remove_column,
            model: table_name.to_s.classify,
            columns: columns.inspect,
            command: command_str(command, *args, options),
            table_name: table_name.inspect,
            indexes: indexes.map { |i| i.name.to_sym.inspect },
            small_table: small_table?(table_name)
        end
      end

      def add_timestamps(table_name, **options)
        @new_columns << [table_name.to_s, "created_at"]
        @new_columns << [table_name.to_s, "updated_at"]

        volatile_default = false
        if !new_or_small_table?(table_name) && !options[:default].nil? &&
           (postgresql_version < Gem::Version.new("11") || (volatile_default = Utils.volatile_default?(connection, :datetime, options[:default])))

          raise_error :add_timestamps_with_default,
            code: [command_str(:add_column_with_default, table_name, :created_at, :datetime, options),
                   command_str(:add_column_with_default, table_name, :updated_at, :datetime, options)].join("\n    "),
            not_null: options[:null] == false,
            volatile_default: volatile_default
        end
      end

      def add_reference(table_name, ref_name, **options)
        # Always added by default in 5.0+
        index = options.fetch(:index, true)

        if index.is_a?(Hash) && index[:using].to_s == "hash" && postgresql_version < Gem::Version.new("10")
          raise_error :add_hash_index
        end

        concurrently_set = index.is_a?(Hash) && index[:algorithm] == :concurrently
        bad_index = index && !concurrently_set

        foreign_key = options.fetch(:foreign_key, false)

        if foreign_key
          foreign_table_name = Utils.foreign_table_name(ref_name, options)
          @foreign_key_tables << foreign_table_name.to_s
        end

        validate_foreign_key = !foreign_key.is_a?(Hash) ||
                               (!foreign_key.key?(:validate) || foreign_key[:validate] == true)
        bad_foreign_key = foreign_key && validate_foreign_key

        if !new_or_small_table?(table_name) && (bad_index || bad_foreign_key)
          raise_error :add_reference,
            code: command_str(:add_reference_concurrently, table_name, ref_name, **options),
            bad_index: bad_index,
            bad_foreign_key: bad_foreign_key
        end

        if !options[:polymorphic]
          type = (options[:type] || :bigint).to_sym
          column_name = "#{ref_name}_id"

          foreign_key_options = foreign_key.is_a?(Hash) ? foreign_key : {}
          check_mismatched_foreign_key_type(table_name, column_name, type, **foreign_key_options)
        end
      end
      alias add_belongs_to add_reference

      def add_index(table_name, column_name, **options)
        if options[:using].to_s == "hash" && postgresql_version < Gem::Version.new("10")
          raise_error :add_hash_index
        end

        if !new_or_small_table?(table_name)
          if options[:algorithm] != :concurrently
            raise_error :add_index,
              command: command_str(:add_index, table_name, column_name, **options.merge(algorithm: :concurrently))
          end

          if options[:algorithm] == :concurrently && index_corruption?
            raise_error :add_index_corruption
          end

          if @removed_indexes.any?
            index = IndexDefinition.new(table: table_name, columns: column_name, **options)
            existing_indexes = connection.indexes(table_name)

            @removed_indexes.each do |removed_index|
              next if !removed_index.intersect?(index)

              if existing_indexes.none? { |existing_index| removed_index.covered_by?(existing_index) }
                raise_error :replace_index
              end
            end
          end

          # Outdated statistics + a new index can hurt performance of existing queries.
          if OnlineMigrations.config.auto_analyze && direction == :up
            connection.execute("ANALYZE #{table_name}")
          end
        end
      end

      def remove_index(table_name, column_name = nil, **options)
        options[:column] ||= column_name

        if options[:algorithm] != :concurrently && !new_or_small_table?(table_name)
          raise_error :remove_index,
            command: command_str(:remove_index, table_name, **options.merge(algorithm: :concurrently))
        end

        index_def = connection.indexes(table_name).find do |index|
          index.name == options[:name].to_s ||
            Array(index.columns).map(&:to_s) == Array(options[:column]).map(&:to_s)
        end

        if index_def
          existing_options = [:name, :columns, :unique, :where, :type, :using, :opclasses].filter_map do |option|
            [option, index_def.public_send(option)] if index_def.respond_to?(option)
          end.to_h

          @removed_indexes << IndexDefinition.new(table: table_name, **existing_options)
        end
      end

      def add_foreign_key(from_table, to_table, **options)
        if !new_or_small_table?(from_table)
          validate = options.fetch(:validate, true)

          if validate
            raise_error :add_foreign_key,
              add_code: command_str(:add_foreign_key, from_table, to_table, **options.merge(validate: false)),
              validate_code: command_str(:validate_foreign_key, from_table, to_table)
          end
        end

        @foreign_key_tables << to_table.to_s
      end

      def validate_foreign_key(*)
        if crud_blocked?
          raise_error :validate_foreign_key
        end
      end

      def add_exclusion_constraint(table_name, _expression, **_options)
        if !new_or_small_table?(table_name)
          raise_error :add_exclusion_constraint
        end
      end

      def add_check_constraint(table_name, expression, **options)
        if !new_or_small_table?(table_name) && options[:validate] != false
          name = options[:name] || check_constraint_name(table_name, expression)

          raise_error :add_check_constraint,
            add_code: command_str(:add_check_constraint, table_name, expression, **options.merge(validate: false)),
            validate_code: command_str(:validate_check_constraint, table_name, name: name)
        end
      end

      def add_unique_constraint(table_name, column_name = nil, **options)
        return if new_or_small_table?(table_name) || options[:using_index] || !column_name

        index_name = Utils.index_name(table_name, column_name)

        raise_error :add_unique_constraint,
          add_index_code: command_str(:add_index, table_name, column_name, unique: true, name: index_name, algorithm: :concurrently),
          add_code: command_str(:add_unique_constraint, table_name, **options.merge(using_index: index_name)),
          remove_code: command_str(:remove_unique_constraint, table_name, column_name)
      end

      def validate_constraint(*)
        if crud_blocked?
          raise_error :validate_constraint
        end
      end
      alias validate_check_constraint validate_constraint
      alias validate_not_null_constraint validate_constraint
      alias validate_text_limit_constraint validate_constraint

      def add_not_null_constraint(table_name, column_name, **options)
        if !new_or_small_table?(table_name) && options[:validate] != false
          raise_error :add_not_null_constraint,
            add_code: command_str(:add_not_null_constraint, table_name, column_name, **options.merge(validate: false)),
            validate_code: command_str(:validate_not_null_constraint, table_name, column_name, **options.except(:validate))
        end
      end

      def add_text_limit_constraint(table_name, column_name, limit, **options)
        if !new_or_small_table?(table_name) && options[:validate] != false
          raise_error :add_text_limit_constraint,
            add_code: command_str(:add_text_limit_constraint, table_name, column_name, limit, **options.merge(validate: false)),
            validate_code: command_str(:validate_text_limit_constraint, table_name, column_name, **options.except(:validate))
        end
      end

      def execute(*)
        raise_error :execute, header: "Possibly dangerous operation"
      end
      alias exec_query execute

      def short_primary_key_type?(options)
        pk_type =
          case options[:id]
          when false
            nil
          when Hash
            options[:id][:type]
          when :primary_key, nil
            # default type is used
            connection.native_database_types[:primary_key].split.first
          else
            options[:id]
          end

        pk_type && !["bigserial", "bigint", "uuid"].include?(pk_type.to_s)
      end

      def collect_foreign_keys(&block)
        collector = ForeignKeysCollector.new
        collector.collect(&block)
        @foreign_key_tables |= collector.referenced_tables
      end

      def check_for_hash_indexes(&block)
        indexes = collect_indexes(&block)
        if indexes.any? { |index| index.using == "hash" }
          raise_error :add_hash_index
        end
      end

      def collect_indexes(&block)
        collector = IndexesCollector.new
        collector.collect(&block)
        collector.indexes
      end

      def new_or_small_table?(table_name)
        new_table?(table_name) || small_table?(table_name)
      end

      def new_table?(table_name)
        @new_tables.include?(table_name.to_s)
      end

      def new_column?(table_name, column_name)
        new_table?(table_name) || @new_columns.include?([table_name.to_s, column_name.to_s])
      end

      def small_table?(table_name)
        OnlineMigrations.config.small_tables.include?(table_name.to_s)
      end

      def postgresql_version
        version =
          if Utils.developer_env? && (target_version = OnlineMigrations.config.target_version)
            target_version.to_s
          else
            database_version = connection.select_value("SHOW server_version_num").to_i
            major = database_version / 10000
            if database_version >= 100000
              minor = database_version % 10000
            else
              minor = (database_version % 10000) / 100
            end
            "#{major}.#{minor}"
          end

        Gem::Version.new(version)
      end

      def connection
        @migration.connection
      end

      def raise_error(message_key, header: nil, **vars)
        return if !OnlineMigrations.config.check_enabled?(message_key, version: version)

        template = OnlineMigrations.config.error_messages.fetch(message_key)

        vars[:migration_name] = @migration.name
        vars[:migration_parent] = "ActiveRecord::Migration[#{Utils.ar_version}]"
        vars[:ar_version] = Utils.ar_version

        message = ERB.new(template, trim_mode: "<>").result_with_hash(vars)

        if (link = ERROR_MESSAGE_TO_LINK[message_key])
          message += "\nFor more details, see https://github.com/fatkodima/online_migrations##{link}"
        end

        @migration.stop!(message, header: header || "Dangerous operation detected")
      end

      def command_str(command, *args)
        arg_list = args[0..-2].map(&:inspect)

        last_arg = args.last
        if last_arg.is_a?(Hash)
          if last_arg.any?
            arg_list << last_arg.map do |k, v|
              case v
              when Hash
                if v.empty?
                  "#{k}: {}"
                else
                  # pretty index: { algorithm: :concurrently }
                  "#{k}: { #{v.map { |k2, v2| "#{k2}: #{v2.inspect}" }.join(', ')} }"
                end
              when Array, Numeric, String, Symbol, TrueClass, FalseClass
                "#{k}: #{v.inspect}"
              else
                "<paste value here>"
              end
            end.join(", ")
          end
        else
          arg_list << last_arg.inspect
        end

        "#{command} #{arg_list.join(', ')}"
      end

      def crud_blocked?
        locks_query = <<~SQL
          SELECT relation::regclass::text
          FROM pg_locks
          WHERE mode IN ('ShareLock', 'ShareRowExclusiveLock', 'ExclusiveLock', 'AccessExclusiveLock')
            AND pid = pg_backend_pid()
        SQL

        connection.select_values(locks_query).any?
      end

      def check_constraint_name(table_name, expression)
        identifier = "#{table_name}_#{expression}_chk"
        hashed_identifier = OpenSSL::Digest::SHA256.hexdigest(identifier).first(10)

        "chk_rails_#{hashed_identifier}"
      end

      def check_constraints(table_name)
        constraints_query = <<~SQL
          SELECT pg_get_constraintdef(oid) AS def
          FROM pg_constraint
          WHERE contype = 'c'
            AND convalidated
            AND conrelid = #{connection.quote(table_name)}::regclass
        SQL

        connection.select_all(constraints_query).to_a
      end

      def check_inheritance_column(table_name, column_name, default)
        if column_name.to_s == ActiveRecord::Base.inheritance_column && !default.nil?
          raise_error :add_inheritance_column,
            table_name: table_name, column_name: column_name,
            model: table_name.to_s.classify, subclass: default
        end
      end

      def check_mismatched_foreign_key_type(table_name, column_name, type, **options)
        column_name = column_name.to_s
        ref_name = column_name.delete_suffix("_id")

        if like_foreign_key?(column_name, type)
          foreign_table_name = Utils.foreign_table_name(ref_name, options)

          if connection.table_exists?(foreign_table_name)
            primary_key = options[:primary_key] || connection.primary_key(foreign_table_name)
            primary_key_column = column_for(foreign_table_name, primary_key)

            if primary_key_column && type != primary_key_column.sql_type.to_sym
              raise_error :mismatched_foreign_key_type,
                table_name: table_name, column_name: column_name
            end
          end
        end
      end

      def like_foreign_key?(column_name, type)
        column_name.end_with?("_id") &&
          [:integer, :bigint, :serial, :bigserial, :uuid].include?(type)
      end

      def indexed?(table_name, column_name)
        connection.indexes(table_name).any? { |index| index.columns.include?(column_name.to_s) }
      end

      def column_for(table_name, column_name)
        connection.columns(table_name).find { |column| column.name == column_name.to_s }
      end

      # From Active Record
      def derive_join_table_name(table1, table2)
        [table1.to_s, table2.to_s].sort.join("\0").gsub(/^(.*_)(.+)\0\1(.+)/, '\1\2_\3').tr("\0", "_")
      end

      def index_corruption?
        postgresql_version >= Gem::Version.new("14.0") &&
          postgresql_version < Gem::Version.new("14.4")
      end

      def run_custom_checks(method, args)
        OnlineMigrations.config.checks.each do |options, check|
          if !options[:start_after] || version > options[:start_after]
            @migration.instance_exec(method, args, &check)
          end
        end
      end
  end
end
