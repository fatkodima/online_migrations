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
        # why do we wrap the transaction in a lock_retries block here?
        # we aren't running the schema statements yet, so we don't know the migration schema_statement command
        #
        # it appers that there are multiple entry points to the lock_retries behaviours
        # one here and one via the method_missing in the migration.rb where we run the schema_statments
        # I'm unsure why this is setup this way, thoughts appreciated.
        migration.connection.with_lock_retries do
          super
        end
      else
        super
      end
    end
  end
end
