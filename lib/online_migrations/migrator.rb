# frozen_string_literal: true

module OnlineMigrations
  # @private
  module Migrator
    def ddl_transaction(migration_or_proxy)
      migration =
        if migration_or_proxy.is_a?(ActiveRecord::MigrationProxy)
          migration_or_proxy.send(:migration)
        else
          migration_or_proxy
        end

      if use_transaction?(migration)
        migration.connection.with_lock_retries do
          super
        end
      else
        super
      end
    end
  end
end
