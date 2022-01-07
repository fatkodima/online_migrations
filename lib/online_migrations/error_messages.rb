# frozen_string_literal: true

module OnlineMigrations
  # @private
  module ErrorMessages
    ERROR_MESSAGES = {
      create_table:
"The `:force` option will destroy existing table. If this is intended, drop the existing table first.
Otherwise, remove the `:force` option.",

      change_column_null:
"Setting NOT NULL on an existing column blocks reads and writes while every row is checked.
A safer approach is to add a NOT NULL check constraint and validate it in a separate transaction.
add_not_null_constraint and validate_not_null_constraint take care of that.

class <%= migration_name %> < <%= migration_parent %>
  disable_ddl_transaction!

  def change
    <%= add_constraint_code %>
<% if backfill_code %>
    <%= backfill_code %>
<% end %>
    <%= validate_constraint_code %>
<% if remove_constraint_code %>
    <%= remove_constraint_code %>
    <%= change_column_null_code %>
<% end %>
  end
end",

      remove_column:
"<% if indexes.any? %>
Removing a column will automatically remove all of the indexes that involved the removed column.
But the indexes would be removed non-concurrently, so you need to safely remove the indexes first:

class <%= migration_name %>RemoveIndexes < <%= migration_parent %>
  disable_ddl_transaction!

  def change
<% indexes.each do |index| %>
    remove_index <%= table_name %>, name: <%= index %>, algorithm: :concurrently
<% end %>
  end
end
<% else %>
ActiveRecord caches database columns at runtime, so if you drop a column, it can cause exceptions until your app reboots.
A safer approach is to:

1. Ignore the column(s):

  class <%= model %> < <%= model_parent %>
    self.ignored_columns = <%= columns %>
  end

2. Deploy
3. Wrap column removing in a safety_assured { ... } block

  class <%= migration_name %> < <%= migration_parent %>
    def change
      safety_assured { <%= command %> }
    end
  end

4. Remove columns ignoring
5. Deploy
<% end %>",

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

      add_foreign_key:
"Adding a foreign key blocks writes on both tables. Add the foreign key without validating existing rows,
and then validate them in a separate transaction.

class <%= migration_name %> < <%= migration_parent %>
  disable_ddl_transaction!

  def change
    <%= add_code %>
    <%= validate_code %>
  end
end",

      validate_foreign_key:
"Validating a foreign key while holding heavy locks on tables is dangerous.
Use disable_ddl_transaction! or a separate migration.",

      add_check_constraint:
"Adding a check constraint blocks reads and writes while every row is checked.
A safer approach is to add the check constraint without validating existing rows,
and then validating them in a separate transaction.

class <%= migration_name %> < <%= migration_parent %>
  disable_ddl_transaction!

  def change
    <%= add_code %>
    <%= validate_code %>
  end
end",

      validate_constraint:
"Validating a constraint while holding heavy locks on tables is dangerous.
Use disable_ddl_transaction! or a separate migration.",

      execute:
"Online Migrations does not support inspecting what happens inside an
execute call, so cannot help you here. Make really sure that what
you're doing is safe before proceeding, then wrap it in a safety_assured { ... } block.",
    }
  end
end
