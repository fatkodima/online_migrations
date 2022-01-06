# frozen_string_literal: true

require "erb"

module OnlineMigrations
  # @private
  class CommandChecker
    def initialize(migration)
      @migration = migration
      @safe = false
    end

    def check(command, *args, **options, &block)
      do_check(command, *args, **options, &block)
      true
    end

    private
      def do_check(command, *args, **options, &block)
        if respond_to?(command, true)
          send(command, *args, **options, &block)
        else
          # assume it is safe
          true
        end
      end

      def add_index(table_name, column_name, **options)
        if options[:algorithm] != :concurrently
          raise_error :add_index,
            command: command_str(:add_index, table_name, column_name, **options.merge(algorithm: :concurrently))
        end
      end

      def raise_error(message_key, **vars)
        template = OnlineMigrations.config.error_messages.fetch(message_key)

        vars[:migration_name] = @migration.name
        vars[:migration_parent] = Utils.migration_parent_string

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
  end
end
