# frozen_string_literal: true

require "erb"

module OnlineMigrations
  # @private
  class CommandChecker
    def initialize(migration)
      @migration = migration
      @safe = false
    end

    def safety_assured
      @prev_value = @safe
      @safe = true
      yield
    ensure
      @safe = @prev_value
    end

    def check(command, *args, **options, &block)
      unless safe?
        do_check(command, *args, **options, &block)
      end

      true
    end

    private
      def safe?
        @safe || ENV["SAFETY_ASSURED"]
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

      def create_table(_table_name, **options)
        raise_error :create_table if options[:force]
      end

      def create_join_table(_table1, _table2, **options)
        raise_error :create_table if options[:force]
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
          columns = [:created_at, :updated_at]
        else
          table_name, reference = args
          columns = [:"#{reference}_id"]
          columns << :"#{reference}_type" if options[:polymorphic]
        end

        indexes = connection.indexes(table_name).select do |index|
          (index.columns & columns.map(&:to_s)).any?
        end

        raise_error :remove_column,
          model: table_name.to_s.classify,
          columns: columns.inspect,
          command: command_str(command, *args),
          table_name: table_name.inspect,
          indexes: indexes.map { |i| i.name.to_sym.inspect }
      end

      def add_index(table_name, column_name, **options)
        if options[:algorithm] != :concurrently
          raise_error :add_index,
            command: command_str(:add_index, table_name, column_name, **options.merge(algorithm: :concurrently))
        end
      end

      def remove_index(table_name, column_name = nil, **options)
        options[:column] ||= column_name

        if options[:algorithm] != :concurrently
          raise_error :remove_index,
            command: command_str(:remove_index, table_name, **options.merge(algorithm: :concurrently))
        end
      end

      def add_foreign_key(from_table, to_table, **options)
        validate = options.fetch(:validate, true)

        if validate
          raise_error :add_foreign_key,
            add_code: command_str(:add_foreign_key, from_table, to_table, **options.merge(validate: false)),
            validate_code: command_str(:validate_foreign_key, from_table, to_table)
        end
      end

      def validate_foreign_key(*)
        if crud_blocked?
          raise_error :validate_foreign_key
        end
      end

      def execute(*)
        raise_error :execute, header: "Possibly dangerous operation"
      end

      def connection
        @migration.connection
      end

      def raise_error(message_key, **vars)
        template = OnlineMigrations.config.error_messages.fetch(message_key)

        vars[:migration_name] = @migration.name
        vars[:migration_parent] = Utils.migration_parent_string
        vars[:model_parent] = Utils.model_parent_string

        message = ERB.new(template, trim_mode: "<>").result_with_hash(vars)

        @migration.stop!(message)
      end

      def command_str(command, *args)
        arg_list = args[0..-2].map(&:inspect)

        last_arg = args.last
        if last_arg.is_a?(Hash)
          if last_arg.any?
            arg_list << last_arg.map do |k, v|
              case v
              when Hash
                # pretty index: { algorithm: :concurrently }
                "#{k}: { #{v.map { |k2, v2| "#{k2}: #{v2.inspect}" }.join(', ')} }"
              when Array, Numeric, String, Symbol, TrueClass, FalseClass
                "#{k}: #{v.inspect}"
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
  end
end
