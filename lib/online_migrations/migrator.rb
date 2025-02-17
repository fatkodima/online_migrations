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
        # Wrap the entire transaction with lock retries so that if the transaction
        # fails to acquire any locks, the whole migration is retried.
        # Note: at this point we don't have visibility into individual DDL commands,
        # so command and arguments will be nil when lock_timeout is called.
        # For command-specific retry behavior, migrations must use `disable_ddl_transaction!`
        migration.connection.with_lock_retries do
          super
        end
      else
        super
      end
    end
  end
end
