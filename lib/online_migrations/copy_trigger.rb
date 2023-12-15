# frozen_string_literal: true

require "openssl"

module OnlineMigrations
  # @private
  class CopyTrigger
    def self.on_table(table_name, connection:)
      new(table_name, connection)
    end

    def name(from_columns, to_columns)
      from_columns, to_columns = normalize_column_names(from_columns, to_columns)

      joined_column_names = from_columns.zip(to_columns).flatten.join("_")
      identifier = "#{table_name}_#{joined_column_names}"
      hashed_identifier = OpenSSL::Digest::SHA256.hexdigest(identifier).first(10)
      "trigger_#{hashed_identifier}"
    end

    def create(from_columns, to_columns, type_cast_functions: {})
      from_columns, to_columns = normalize_column_names(from_columns, to_columns)
      trigger_name = name(from_columns, to_columns)
      assignment_clauses = assignment_clauses_for_columns(from_columns, to_columns, type_cast_functions)

      connection.execute(<<~SQL)
        CREATE OR REPLACE FUNCTION #{trigger_name}() RETURNS TRIGGER AS $$
        BEGIN
          #{assignment_clauses};
          RETURN NEW;
        END;
        $$ LANGUAGE plpgsql;
      SQL

      connection.execute(<<~SQL)
        DROP TRIGGER IF EXISTS #{trigger_name} ON #{quoted_table_name}
      SQL

      connection.execute(<<~SQL)
        CREATE TRIGGER #{trigger_name}
          BEFORE INSERT OR UPDATE
          ON #{quoted_table_name}
          FOR EACH ROW
          EXECUTE PROCEDURE #{trigger_name}();
      SQL
    end

    def remove(from_columns, to_columns)
      trigger_name = name(from_columns, to_columns)

      connection.execute("DROP TRIGGER IF EXISTS #{trigger_name} ON #{quoted_table_name}")
      connection.execute("DROP FUNCTION IF EXISTS #{trigger_name}()")
    end

    private
      attr_reader :table_name, :connection

      def initialize(table_name, connection)
        @table_name = table_name
        @connection = connection
      end

      def quoted_table_name
        @quoted_table_name ||= connection.quote_table_name(table_name)
      end

      def normalize_column_names(from_columns, to_columns)
        from_columns = Array.wrap(from_columns)
        to_columns = Array.wrap(to_columns)

        if from_columns.size != to_columns.size
          raise ArgumentError, "Number of source and destination columns must match"
        end

        [from_columns, to_columns]
      end

      def assignment_clauses_for_columns(from_columns, to_columns, type_cast_functions)
        combined_column_names = to_columns.zip(from_columns)

        assignment_clauses = combined_column_names.map do |(new_name, old_name)|
          quoted_new_name = connection.quote_column_name(new_name)
          quoted_old_name = connection.quote_column_name(old_name)
          type_cast_function = type_cast_functions[old_name]

          if type_cast_function
            "NEW.#{quoted_new_name} := #{type_cast_function.gsub(old_name.to_s, "NEW.#{quoted_old_name}")}"
          else
            "NEW.#{quoted_new_name} := NEW.#{quoted_old_name}"
          end
        end

        assignment_clauses.join(";\n  ")
      end
  end
end
