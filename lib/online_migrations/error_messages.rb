# frozen_string_literal: true

module OnlineMigrations
  # @private
  module ErrorMessages
    ERROR_MESSAGES = {
      add_index:
"Adding an index non-concurrently blocks writes. Instead, use:

class <%= migration_name %> < <%= migration_parent %>
  disable_ddl_transaction!

  def change
    <%= command %>
  end
end",
    }
  end
end
