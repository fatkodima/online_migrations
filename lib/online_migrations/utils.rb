# frozen_string_literal: true

module OnlineMigrations
  # @private
  module Utils
    class << self
      def ar_version
        ActiveRecord.version.to_s.to_f
      end

      def developer_env?
        defined?(Rails) && (Rails.env.development? || Rails.env.test?)
      end

      def say(message)
        message = "[online_migrations] #{message}"
        if (migration = OnlineMigrations.current_migration)
          migration.say(message)
        elsif (logger = ActiveRecord::Base.logger)
          logger.info(message)
        end
      end

      def migration_parent
        if ar_version <= 4.2
          ActiveRecord::Migration
        else
          ActiveRecord::Migration[ar_version]
        end
      end

      def migration_parent_string
        if ar_version <= 4.2
          "ActiveRecord::Migration"
        else
          "ActiveRecord::Migration[#{ar_version}]"
        end
      end

      def model_parent_string
        if ar_version >= 5.0
          "ApplicationRecord"
        else
          "ActiveRecord::Base"
        end
      end

      def define_model(connection, table_name)
        Class.new(ActiveRecord::Base) do
          self.table_name = table_name
          self.inheritance_column = :_type_disabled

          @online_migrations_connection = connection

          def self.connection
            @online_migrations_connection
          end
        end
      end

      def foreign_table_name(ref_name, options)
        options.fetch(:to_table) do
          ActiveRecord::Base.pluralize_table_names ? ref_name.to_s.pluralize : ref_name
        end
      end

      def ar_partial_writes?
        ActiveRecord::Base.public_send(ar_partial_writes_setting)
      end

      def ar_partial_writes_setting
        if Utils.ar_version >= 7.0
          "partial_inserts"
        else
          "partial_writes"
        end
      end

      FUNCTION_CALL_RE = /(\w+)\s*\(/
      private_constant :FUNCTION_CALL_RE

      def volatile_default?(connection, type, value)
        return false unless value.is_a?(Proc) || (type.to_s == "uuid" && value.is_a?(String))

        value = value.call if value.is_a?(Proc)
        return false if !value.is_a?(String)

        value.scan(FUNCTION_CALL_RE).any? { |(function_name)| volatile_function?(connection, function_name.downcase) }
      end

      def volatile_function?(connection, function_name)
        query = <<~SQL
          SELECT provolatile
          FROM pg_catalog.pg_proc
          WHERE proname = #{connection.quote(function_name)}
        SQL

        connection.select_value(query) == "v"
      end
    end
  end
end
