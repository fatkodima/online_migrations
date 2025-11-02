# frozen_string_literal: true

require "openssl"

module OnlineMigrations
  # @private
  module Utils
    class << self
      def ar_version
        ActiveRecord.version.to_s.to_f
      end

      def env
        if defined?(Rails.env)
          Rails.env
        else
          # default to production for safety
          ENV["RACK_ENV"] || "production"
        end
      end

      def developer_env?
        env == "development" || env == "test"
      end

      def say(message)
        message = "[online_migrations] #{message}"
        if (migration = OnlineMigrations.current_migration)
          migration.say(message)
        elsif (logger = ActiveRecord::Base.logger)
          logger.info(message)
        end
      end

      def raise_or_say(message)
        if developer_env? && !multiple_databases?
          raise message
        else
          say(message)
        end
      end

      def raise_in_prod_or_say_in_dev(message)
        if developer_env?
          say(message)
        else
          raise message
        end
      end

      def warn(message)
        Kernel.warn("[online_migrations] #{message}")
      end

      def define_model(table_name)
        Class.new(ActiveRecord::Base) do
          self.table_name = table_name
          self.inheritance_column = :_type_disabled
        end
      end

      def to_bool(value)
        value.to_s.match?(/^true|t|yes|y|1|on$/i)
      end

      def foreign_table_name(ref_name, options)
        options.fetch(:to_table) do
          ActiveRecord::Base.pluralize_table_names ? ref_name.to_s.pluralize : ref_name
        end
      end

      # Returns estimated rows count for a table.
      # https://www.citusdata.com/blog/2016/10/12/count-performance/
      def estimated_count(connection, table_name)
        quoted_table = connection.quote(table_name)

        count = connection.select_value(<<~SQL)
          SELECT
            (reltuples / COALESCE(NULLIF(relpages, 0), 1)) *
            (pg_relation_size(#{quoted_table}) / (current_setting('block_size')::integer))
          FROM pg_catalog.pg_class
          WHERE relname = #{quoted_table}
            AND relnamespace = current_schema()::regnamespace
        SQL

        if count
          count = count.to_i
          # If the table has never yet been vacuumed or analyzed, reltuples contains -1
          # indicating that the row count is unknown.
          count = 0 if count < 0
          count
        end
      end

      FUNCTION_CALL_RE = /(\w+)\s*\(/
      private_constant :FUNCTION_CALL_RE

      def volatile_default?(connection, type, value)
        return false if !(value.is_a?(Proc) || (type.to_s == "uuid" && value.is_a?(String)))

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

      def find_connection_class(model)
        model.ancestors.find do |parent|
          parent == ActiveRecord::Base ||
            (parent.is_a?(Class) && parent.abstract_class?)
        end
      end

      def shard_names(model)
        model.ancestors.each do |ancestor|
          # There is no official method to get shard names from the model.
          # This is the way that currently is used in ActiveRecord tests themselves.
          pool_manager = ActiveRecord::Base.connection_handler.send(:get_pool_manager, ancestor.name)

          if pool_manager
            shards_with_database_tasks = pool_manager.shard_names.select do |shard_name|
              pool_config = pool_manager.get_pool_config(:writing, shard_name)
              pool_config.db_config.database_tasks? if pool_config
            end

            return shards_with_database_tasks
          end
        end
      end

      def multiple_databases?
        db_config = ActiveRecord::Base.configurations.configs_for(env_name: env)
        db_config.reject(&:replica?).size > 1
      end

      def run_background_migrations_inline?
        run_inline = OnlineMigrations.config.run_background_migrations_inline
        run_inline && run_inline.call
      end
    end
  end
end
