# frozen_string_literal: true

module OnlineMigrations
  module SchemaStatements
    # Extends default method to be idempotent and automatically recreate invalid indexes.
    #
    # @see https://edgeapi.rubyonrails.org/classes/ActiveRecord/ConnectionAdapters/SchemaStatements.html#method-i-add_index
    #
    def add_index(table_name, column_name, **options)
      algorithm = options[:algorithm]

      __ensure_not_in_transaction! if algorithm == :concurrently

      column_names = __index_column_names(column_name || options[:column])

      index_name = options[:name]
      index_name ||= index_name(table_name, column_names)

      if index_exists?(table_name, column_name, **options)
        if __index_valid?(index_name)
          Utils.say("Index was not created because it already exists (this may be due to an aborted migration "\
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

      if index_exists?(table_name, column_name, **options)
        disable_statement_timeout do
          # "DROP INDEX CONCURRENTLY" requires a "SHARE UPDATE EXCLUSIVE" lock.
          # It only conflicts with constraint validations, other creating/removing indexes,
          # and some "ALTER TABLE"s.
          super(table_name, **options.merge(column: column_names))
        end
      else
        Utils.say("Index was not removed because it does not exist (this may be due to an aborted migration "\
          "or similar): table_name: #{table_name}, column_name: #{column_name}")
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

    private
      # Private methods are prefixed with `__` to avoid clashes with existing or future
      # ActiveRecord methods
      def __ensure_not_in_transaction!(method_name = caller[0])
        if transaction_open?
          raise <<~MSG
            `#{method_name}` cannot run inside a transaction block.

            You can remove transaction block by calling `disable_ddl_transaction!` in the body of
            your migration class.
          MSG
        end
      end

      def __index_column_names(column_names)
        if column_names.is_a?(String) && /\W/.match?(column_names)
          column_names
        else
          Array(column_names)
        end
      end

      def __index_valid?(index_name)
        select_value <<~SQL
          SELECT indisvalid
          FROM pg_index i
          JOIN pg_class c
            ON i.indexrelid = c.oid
          WHERE c.relname = #{quote(index_name)}
        SQL
      end
  end
end
