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
    end
  end
end
