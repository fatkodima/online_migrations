# frozen_string_literal: true

require "erb"
require "openssl"
require "set"

module OnlineMigrations
  # @private
  class CommandChecker
    attr_accessor :direction

    def initialize(migration)
      @migration = migration
      @safe = false
      @new_tables = []
      @lock_timeout_checked = false
      @foreign_key_tables = Set.new
      @removed_indexes = []
    end

    def safety_assured
      @prev_value = @safe
      @safe = true
      yield
    ensure
      @safe = @prev_value
    end

    def check(command, *args, &block)
      check_lock_timeout

      unless safe?
        do_check(command, *args, &block)

        run_custom_checks(command, args)

        if @foreign_key_tables.count { |t| !new_table?(t) } > 1
          raise_error :multiple_foreign_keys
        end
      end

      true
    end

    private
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
        @safe ||
          ENV["SAFETY_ASSURED"] ||
          (direction == :down && !OnlineMigrations.config.check_down) ||
          version <= OnlineMigrations.config.start_after
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
        volatile_default = false
        if !new_or_small_table?(table_name) && !options[:default].nil? &&
           (postgresql_version < Gem::Version.new("11") || (volatile_default = Utils.volatile_default?(connection, type, options[:default])))

          raise_error :add_column_with_default,
            code: command_str(:add_column_with_default, table_name, column_name, type, options),
            not_null: options[:null] == false,
            volatile_default: volatile_default
        end

        if type == :json
          raise_error :add_column_json,
            code: command_str(:add_column, table_name, column_name, :jsonb, options)
        end

        type = :bigint if type == :integer && options[:limit] == 8
        check_mismatched_foreign_key_type(table_name, column_name, type)
      end

      def add_column_with_default(table_name, column_name, type, **options)
        if type == :json
          raise_error :add_column_json,
            code: command_str(:add_column_with_default, table_name, column_name, :jsonb, options)
        end
      end

      def rename_column(table_name, column_name, new_column, **)
        if !new_table?(table_name)
          raise_error :rename_column,
            table_name: table_name,
            column_name: column_name,
            new_column: new_column,
            model: table_name.to_s.classify,
            partial_writes: Utils.ar_partial_writes?,
            partial_writes_setting: Utils.ar_partial_writes_setting
        end
      end

      def change_column(table_name, column_name, type, **options)
        return if new_table?(table_name)

        type = type.to_sym

        existing_column = connection.columns(table_name).find { |c| c.name == column_name.to_s }
        if existing_column
          existing_type = existing_column.type.to_sym

          safe =
            case type
            when :string
              # safe to increase limit or remove it
              # not safe to decrease limit or add a limit
              case existing_type
              when :string
                !options[:limit] || (existing_column.limit && options[:limit] >= existing_column.limit)
              when :text
                !options[:limit]
              end
            when :text
              # safe to change varchar to text (and text to text)
              [:string, :text].include?(existing_type)
            when :numeric, :decimal
              # numeric and decimal are equivalent and can be used interchangably
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
              [:timestamp, :timestamptz].include?(existing_type) &&
              postgresql_version >= Gem::Version.new("12") &&
              connection.select_value("SHOW timezone") == "UTC"
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
              cleanup_code: command_str(:cleanup_change_column_type_concurrently, table_name, column_name),
              cleanup_down_code: command_str(:initialize_column_type_change, table_name, column_name, existing_type)
          end
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
              backfill_code: nil,
              validate_constraint_code: command_str(:validate_not_null_constraint, table_name, column_name, name: constraint_name),
              remove_constraint_code: nil,
            }

            if !default.nil?
              vars[:backfill_code] = command_str(:update_column_in_batches, table_name, column_name, default)
            end

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
            (index.columns & columns).any?
          end

          raise_error :remove_column,
            model: table_name.to_s.classify,
            columns: columns.inspect,
            command: command_str(command, *args),
            table_name: table_name.inspect,
            indexes: indexes.map { |i| i.name.to_sym.inspect }
        end
      end

      def add_timestamps(table_name, **options)
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
        index = options.fetch(:index) { Utils.ar_version >= 5.0 }

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

        unless options[:polymorphic]
          type = options[:type] || (Utils.ar_version >= 5.1 ? :bigint : :integer)
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

          if @removed_indexes.any?
            index = IndexDefinition.new(table: table_name, columns: column_name, **options)
            existing_indexes = connection.indexes(table_name)

            @removed_indexes.each do |removed_index|
              next unless removed_index.intersect?(index)

              unless existing_indexes.any? { |existing_index| removed_index.covered_by?(existing_index) }
                raise_error :replace_index
              end
            end
          end
        end
      end

      def remove_index(table_name, column_name = nil, **options)
        options[:column] ||= column_name

        if options[:algorithm] != :concurrently && !new_or_small_table?(table_name)
          raise_error :remove_index,
            command: command_str(:remove_index, table_name, **options.merge(algorithm: :concurrently))
        end

        if options[:column] || options[:name]
          options[:column] ||= connection.indexes(table_name).find { |index| index.name == options[:name].to_s }
          @removed_indexes << IndexDefinition.new(table: table_name, columns: options.delete(:column), **options)
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

      def add_check_constraint(table_name, expression, **options)
        if !new_or_small_table?(table_name) && options[:validate] != false
          name = options[:name] || check_constraint_name(table_name, expression)

          raise_error :add_check_constraint,
            add_code: command_str(:add_check_constraint, table_name, expression, **options.merge(validate: false)),
            validate_code: command_str(:validate_check_constraint, table_name, name: name)
        end
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
        small_tables = OnlineMigrations.config.small_tables

        new_table?(table_name) ||
          small_tables.include?(table_name.to_s)
      end

      def new_table?(table_name)
        @new_tables.include?(table_name.to_s)
      end

      def postgresql_version
        version =
          if Utils.developer_env? && (target_version = OnlineMigrations.config.target_version)
            target_version.to_s
          else
            # For rails 6.0+ we can use connection.database_version
            pg_connection = connection.instance_variable_get(:@connection)
            database_version = pg_connection.server_version
            patch = database_version % 100
            database_version /= 100
            minor = database_version % 100
            database_version /= 100
            major = database_version
            "#{major}.#{minor}.#{patch}"
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
        vars[:migration_parent] = Utils.migration_parent_string
        vars[:model_parent] = Utils.model_parent_string
        vars[:ar_version] = Utils.ar_version

        if RUBY_VERSION >= "2.6"
          message = ERB.new(template, trim_mode: "<>").result_with_hash(vars)
        else
          # `result_with_hash` was added in ruby 2.5
          b = TOPLEVEL_BINDING.dup
          vars.each_pair do |key, value|
            b.local_variable_set(key, value)
          end
          message = ERB.new(template, nil, "<>").result(b)
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
        locks_query = <<-SQL.strip_heredoc
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
        constraints_query = <<-SQL.strip_heredoc
          SELECT pg_get_constraintdef(oid) AS def
          FROM pg_constraint
          WHERE contype = 'c'
            AND convalidated
            AND conrelid = #{connection.quote(table_name)}::regclass
        SQL

        connection.select_all(constraints_query).to_a
      end

      def check_mismatched_foreign_key_type(table_name, column_name, type, **options)
        column_name = column_name.to_s
        ref_name = column_name.sub(/_id\z/, "")

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

      def column_for(table_name, column_name)
        connection.columns(table_name).find { |column| column.name == column_name.to_s }
      end

      # From ActiveRecord
      def derive_join_table_name(table1, table2)
        [table1.to_s, table2.to_s].sort.join("\0").gsub(/^(.*_)(.+)\0\1(.+)/, '\1\2_\3').tr("\0", "_")
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
