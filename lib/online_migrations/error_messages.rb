# frozen_string_literal: true

module OnlineMigrations
  # @private
  module ErrorMessages
    ERROR_MESSAGES = {
      short_primary_key_type:
"Using short integer types for primary keys is dangerous due to the risk of running
out of IDs on inserts. Better to use one of 'bigint', 'bigserial' or 'uuid'.",

      create_table:
"The `:force` option will destroy existing table. If this is intended, drop the existing table first.
Otherwise, remove the `:force` option.",

      rename_table:
"Renaming a table that's in use will cause errors in your application.
migration_helpers provides a safer approach to do this:

1. Instruct Rails that you are going to rename a table:

  OnlineMigrations.config.table_renames = {
    <%= table_name.to_s.inspect %> => <%= new_name.to_s.inspect %>
  }

2. Deploy
3. Tell the database that you are going to rename a table. This will not actually rename any tables,
nor any data/indexes/foreign keys copying will be made, so will be very fast.
It will use a VIEW to work with both table names simultaneously:

  class Initialize<%= migration_name %> < <%= migration_parent %>
    def change
      initialize_table_rename <%= table_name.inspect %>, <%= new_name.inspect %>
    end
  end

4. Replace usages of the old table with a new table in the codebase
5. Remove the table rename config from step 1
6. Deploy
7. Remove the VIEW created on step 3:

  class Finalize<%= migration_name %> < <%= migration_parent %>
    def change
      finalize_table_rename <%= table_name.inspect %>, <%= new_name.inspect %>
    end
  end

8. Deploy",

      add_column_with_default:
"Adding a column with a non-null default blocks reads and writes while the entire table is rewritten.

A safer approach is to:
1. add the column without a default value
2. change the column default
3. backfill existing rows with the new value
<% if not_null %>
4. add the NOT NULL constraint
<% end %>

<% unless volatile_default %>
add_column_with_default takes care of all this steps:

class <%= migration_name %> < <%= migration_parent %>
  disable_ddl_transaction!

  def change
    <%= code %>
  end
end
<% end %>",

      add_column_json:
"There's no equality operator for the json column type, which can cause errors for
existing SELECT DISTINCT queries in your application. Use jsonb instead.

class <%= migration_name %> < <%= migration_parent %>
  def change
    <%= code %>
  end
end",

      rename_column:
"Renaming a column that's in use will cause errors in your application.
migration_helpers provides a safer approach to do this:

1. Instruct Rails that you are going to rename a column:

  OnlineMigrations.config.column_renames = {
    <%= table_name.to_s.inspect %> => {
      <%= column_name.to_s.inspect %> => <%= new_column.to_s.inspect %>
    }
  }
<% unless partial_writes %>
  NOTE: You also need to temporarily enable partial writes until the process of column rename is fully done.
  # config/application.rb
  config.active_record.<%= partial_writes_setting %> = true
<% end %>

2. Deploy
3. Tell the database that you are going to rename a column. This will not actually rename any columns,
nor any data/indexes/foreign keys copying will be made, so will be instantaneous.
It will use a combination of a VIEW and column aliasing to work with both column names simultaneously:

  class Initialize<%= migration_name %> < <%= migration_parent %>
    def change
      initialize_column_rename <%= table_name.inspect %>, <%= column_name.inspect %>, <%= new_column.inspect %>
    end
  end

4. Replace usages of the old column with a new column in the codebase
5. Deploy
6. Remove the column rename config from step 1
7. Remove the VIEW created in step 3:

  class Finalize<%= migration_name %> < <%= migration_parent %>
    def change
      finalize_column_rename <%= table_name.inspect %>, <%= column_name.inspect %>, <%= new_column.inspect %>
    end
  end

8. Deploy",

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

      add_timestamps_with_default:
"Adding timestamps columns with non-null defaults blocks reads and writes while the entire table is rewritten.

A safer approach is to, for both timestamps columns:
1. add the column without a default value
2. change the column default
3. backfill existing rows with the new value
<% if not_null %>
4. add the NOT NULL constraint
<% end %>

<% unless volatile_default %>
add_column_with_default takes care of all this steps:

class <%= migration_name %> < <%= migration_parent %>
  disable_ddl_transaction!

  def change
    <%= code %>
  end
end
<% end %>",

      add_reference:
"<% if bad_foreign_key %>
Adding a foreign key blocks writes on both tables.
<% end %>
<% if bad_index %>
Adding an index non-concurrently blocks writes.
<% end %>
Instead, use add_reference_concurrently helper. It will create a reference and take care of safely adding <% if bad_foreign_key %>a foreign key<% end %><% if bad_index && bad_foreign_key %> and <% end %><% if bad_index %>index<% end %>.

class <%= migration_name %> < <%= migration_parent %>
  disable_ddl_transaction!

  def change
    <%= code %>
  end
end",

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
