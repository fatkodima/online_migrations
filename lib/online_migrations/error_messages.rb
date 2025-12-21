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

      change_table:
"Online Migrations does not support inspecting what happens inside a
change_table block, so cannot help you here. Make really sure that what
you're doing is safe before proceeding, then wrap it in a safety_assured { ... } block.",

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

      add_column_with_default_null:
"Adding a column with a null default blocks reads and writes while the entire table is rewritten.
Instead, add the column without a default value.

class <%= migration_name %> < <%= migration_parent %>
  def change
    <%= code %>
  end
end",

      add_column_generated_stored:
"Adding a stored generated column blocks reads and writes while the entire table is rewritten.
Add a non-generated column and use callbacks or triggers instead.",

      add_column_json:
"There's no equality operator for the json column type, which can cause errors for
existing SELECT DISTINCT queries in your application. Use jsonb instead.

class <%= migration_name %> < <%= migration_parent %>
  def change
    <%= code %>
  end
end",

      add_inheritance_column:
"'<%= column_name %>' column is used for single table inheritance. Adding it might cause errors in old instances of your application.

After the migration was ran and the column was added, but before the code is fully deployed to all instances,
an old instance may be restarted (due to an error etc). And when it will fetch '<%= model %>' records from the database,
'<%= model %>' will look for a '<%= subclass %>' subclass (from the '<%= column_name %>' column) and fail to locate it unless it is already defined.

A safer approach is to:

1. ignore the column:

  class <%= model %> < ApplicationRecord
    self.ignored_columns += [\"<%= column_name %>\"]
  end

2. deploy
3. remove the column ignoring from step 1 and apply initial code changes
4. deploy",

      rename_column:
"Renaming a column that's in use will cause errors in your application.
migration_helpers provides a safer approach to do this:

1. Instruct Rails that you are going to rename a column:

  OnlineMigrations.config.column_renames = {
    <%= table_name.to_s.inspect %> => {
      <%= column_name.to_s.inspect %> => <%= new_column.to_s.inspect %>
    }
  }
<% unless ActiveRecord::Base.partial_inserts %>

  NOTE: You also need to temporarily enable partial writes (is disabled by default in Active Record >= 7)
  until the process of column rename is fully done.
  # config/application.rb
  config.active_record.partial_inserts = true
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
<% if ActiveRecord::Base.enumerate_columns_in_select_statements %>
5. Ignore old column

  self.ignored_columns += [:<%= column_name %>]

6. Deploy
7. Remove the column rename config from step 1
8. Remove the column ignore from step 5
9. Remove the VIEW created in step 3 and finally rename the column:

  class Finalize<%= migration_name %> < <%= migration_parent %>
    def change
      finalize_column_rename :<%= table_name %>, :<%= column_name %>, :<%= new_column %>
    end
  end

10. Deploy
<% else %>
5. Deploy
6. Remove the column rename config from step 1
7. Remove the VIEW created in step 3 and finally rename the column:

  class Finalize<%= migration_name %> < <%= migration_parent %>
    def change
      finalize_column_rename :<%= table_name %>, :<%= column_name %>, :<%= new_column %>
    end
  end

8. Deploy
<% end %>",

      change_column_with_not_null:
"Changing the type is safe, but setting NOT NULL is not.",

      change_column:
"Changing the type of an existing column blocks reads and writes while the entire table is rewritten.
A safer approach can be accomplished in several steps:

1. Create a new column and keep column's data in sync:

  class Initialize<%= migration_name %> < <%= migration_parent %>
    def change
      <%= initialize_change_code %>
    end
  end

**Note**: `initialize_column_type_change` accepts additional options (like `:limit`, `:default` etc)
which will be passed to `add_column` when creating a new column, so you can override previous values.

2. Backfill data from the old column to the new column:

  class Backfill<%= migration_name %> < <%= migration_parent %>
    disable_ddl_transaction!

    def up
      # You can use `backfill_column_for_type_change_in_background` if want to
      # backfill using background migrations.
      <%= backfill_code %>
    end

    def down
      # no op
    end
  end

3. Make sure your application works with values in both formats (when read from the database, converting
during writes works automatically). For most column type changes, this does not need any updates in the app.
4. Deploy
5. Copy indexes, foreign keys, check constraints, NOT NULL constraint, swap new column in place:

  class Finalize<%= migration_name %> < <%= migration_parent %>
    disable_ddl_transaction!

    def change
      <%= finalize_code %>
    end
  end

6. Deploy
7. Finally, if everything works as expected, remove copy trigger and old column:

  class Cleanup<%= migration_name %> < <%= migration_parent %>
    disable_ddl_transaction!

    def up
      <%= cleanup_code %>
    end

    def down
      <%= cleanup_down_code %>
    end
  end

8. Remove changes from step 3, if any
9. Deploy",

      change_column_constraint: "Changing the type of a column that has check constraints blocks reads and writes
while every row is checked. Drop the check constraints on the column before
changing the type and add them back afterwards.

class <%= migration_name %> < <%= migration_parent %>
  def change
    <%= change_column_code %>
  end
end

class Validate<%= migration_name %> < <%= migration_parent %>
  def change
    <%= validate_constraint_code %>
  end
end",

      change_column_default:
"Partial writes are enabled, which can cause incorrect values
to be inserted when changing the default value of a column.
Disable partial writes in config/application.rb:

config.active_record.partial_inserts = false",

      change_column_null:
"Setting NOT NULL on an existing column blocks reads and writes while every row is checked.
A safer approach is to add a NOT NULL check constraint and validate it in a separate transaction.
add_not_null_constraint and validate_not_null_constraint take care of that.

class <%= migration_name %> < <%= migration_parent %>
  disable_ddl_transaction!

  def change
    <%= add_constraint_code %>
<% unless default_value.nil? %>

    # Passing a default value to change_column_null runs a single UPDATE query,
    # which can cause downtime. Instead, backfill the existing rows in batches.
    update_column_in_batches(:<%= table_name %>, :<%= column_name %>, <%= default_value.inspect %>) do |relation|
      relation.where(<%= column_name %>: nil)
    end

<% end %>
    # You can use `validate_constraint_in_background` if you have a very large table
    # and want to validate the constraint using background schema migrations.
    <%= validate_constraint_code %>
<% if remove_constraint_code %>

    <%= change_column_null_code %>
    <%= remove_constraint_code %>
<% end %>
  end
end",

      remove_column:
"<% if !small_table && indexes.any? %>
Removing a column will automatically remove all the indexes that include this column.
Indexes will be removed non-concurrently, so you need to safely remove them first:

class <%= migration_name %>RemoveIndexes < <%= migration_parent %>
  disable_ddl_transaction!

  def change
<% indexes.each do |index| %>
    remove_index <%= table_name %>, name: <%= index %>, algorithm: :concurrently
<% end %>
  end
end
<% else %>
Active Record caches database columns at runtime, so if you drop a column, it can cause exceptions until your app reboots.
A safer approach is to:

1. Ignore the column:

  class <%= model %> < ApplicationRecord
    self.ignored_columns += <%= columns %>
  end

2. Deploy
3. Wrap column removing in a safety_assured { ... } block

  class <%= migration_name %> < <%= migration_parent %>
    def change
      safety_assured { <%= command %> }
    end
  end

4. Remove column ignoring from step 1
5. Deploy
<% end %>",

      add_timestamps_with_default:
"Adding timestamp columns with volatile defaults blocks reads and writes while the entire table is rewritten.

A safer approach is to, for both timestamps columns:
1. add the column without a default value
2. change the column default
3. backfill existing rows with the new value
<% if not_null %>
4. add the NOT NULL constraint
<% end %>

add_column_with_default takes care of all this steps:

class <%= migration_name %> < <%= migration_parent %>
  disable_ddl_transaction!

  def change
    <%= code %>
  end
end",

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

      add_index_corruption:
"Adding an index concurrently can cause silent data corruption in PostgreSQL 14.0 to 14.3.
Upgrade PostgreSQL before adding new indexes, or wrap this step in a safety_assured { ... }
block to accept the risk.",

      remove_index:
"Removing an index non-concurrently blocks writes. Instead, use:

class <%= migration_name %> < <%= migration_parent %>
  disable_ddl_transaction!

  def change
    <%= command %>
  end
end",

      replace_index:
"Removing an old index before replacing it with the new one might result in slow queries while building the new index.
A safer approach is to create the new index and then delete the old one.",

      add_foreign_key:
"Adding a foreign key blocks writes on both tables. Instead, add the foreign key without validating existing rows,
then validate them in a separate migration.

class <%= migration_name %> < <%= migration_parent %>
  def change
    <%= add_code %>
  end
end

class Validate<%= migration_name %> < <%= migration_parent %>
  def change
    # You can use `validate_foreign_key_in_background` if you have a very large table
    # and want to validate the foreign key using background schema migrations.
    <%= validate_code %>
  end
end",

      validate_foreign_key:
"Validating a foreign key while holding heavy locks on tables is dangerous.
Use disable_ddl_transaction! or a separate migration.",

      add_exclusion_constraint:
"Adding an exclusion constraint blocks reads and writes while every row is checked.",

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

      add_unique_constraint:
"Adding a unique constraint blocks reads and writes while the underlying index is being built.
A safer approach is to create a unique index first, and then create a unique constraint using that index.

class <%= migration_name %>AddIndex < <%= migration_parent %>
  disable_ddl_transaction!

  def change
    <%= add_index_code %>
  end
end

class <%= migration_name %> < <%= migration_parent %>
  def up
    <%= add_code %>
  end

  def down
    <%= remove_code %>
  end
end",

      validate_constraint:
"Validating a constraint while holding heavy locks on tables is dangerous.
Use disable_ddl_transaction! or a separate migration.",

      add_not_null_constraint:
"Adding a NOT NULL constraint blocks reads and writes while every row is checked.
A safer approach is to add the NOT NULL check constraint without validating existing rows,
and then validating them in a separate migration.

class <%= migration_name %> < <%= migration_parent %>
  def change
    <%= add_code %>
  end
end

class <%= migration_name %>Validate < <%= migration_parent %>
  def change
    <%= validate_code %>
  end
end",

      add_text_limit_constraint:
"Adding a limit on the text column blocks reads and writes while every row is checked.
A safer approach is to add the limit check constraint without validating existing rows,
and then validating them in a separate migration.

class <%= migration_name %> < <%= migration_parent %>
  def change
    <%= add_code %>
  end
end

class <%= migration_name %>Validate < <%= migration_parent %>
  def change
    <%= validate_code %>
  end
end",

      execute:
"Online Migrations does not support inspecting what happens inside an
execute call, so cannot help you here. Make really sure that what
you're doing is safe before proceeding, then wrap it in a safety_assured { ... } block.",

      multiple_foreign_keys:
"Adding multiple foreign keys in a single migration blocks writes on all involved tables until migration is completed.
Avoid adding foreign key more than once per migration file, unless the source and target tables are identical.",

      drop_table_multiple_foreign_keys:
"Dropping a table with multiple foreign keys blocks reads and writes on all involved tables until migration is completed.
Remove all the foreign keys first.",

      mismatched_foreign_key_type:
"<%= table_name %>.<%= column_name %> references a column of different type - foreign keys should be of the same type as the referenced primary key.
Otherwise, there's a risk of errors caused by IDs representable by one type but not the other.",
    }
  end
end
