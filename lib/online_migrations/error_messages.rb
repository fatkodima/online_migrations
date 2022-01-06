# frozen_string_literal: true

module OnlineMigrations
  # @private
  module ErrorMessages
    ERROR_MESSAGES = {
      create_table:
"The `:force` option will destroy existing table. If this is intended, drop the existing table first.
Otherwise, remove the `:force` option.",

      add_index:
"Adding an index non-concurrently blocks writes. Instead, use:

class <%= migration_name %> < <%= migration_parent %>
  disable_ddl_transaction!

  def change
    <%= command %>
  end
end",

      remove_index:
"Removing an index non-concurrently blocks writes. Instead, use:

class <%= migration_name %> < <%= migration_parent %>
  disable_ddl_transaction!

  def change
    <%= command %>
  end
end",

      execute:
"Online Migrations does not support inspecting what happens inside an
execute call, so cannot help you here. Make really sure that what
you're doing is safe before proceeding, then wrap it in a safety_assured { ... } block.",
    }
  end
end
