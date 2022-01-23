# OnlineMigrations

Catch unsafe PostgreSQL migrations in development and run them easier in production.

:white_check_mark: Detects potentially dangerous operations\
:white_check_mark: Prevents them from running by default\
:white_check_mark: Provides instructions and helpers on safer ways to do what you want

**Note**: You probably don't need this gem for smaller projects, as operations that are unsafe at scale can be perfectly safe on smaller, low-traffic tables.

[![Build Status](https://github.com/fatkodima/online_migrations/actions/workflows/test.yml/badge.svg?branch=master)](https://github.com/fatkodima/online_migrations/actions/workflows/test.yml)

## Requirements

- Ruby 2.1+
- Rails 4.2+
- PostgreSQL 9.6+

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'online_migrations'
```

And then run:

```sh
$ bundle install
$ bin/rails generate online_migrations:install
```

**Note**: If you do not have plans on using [background migrations](BACKGROUND_MIGRATIONS.md) feature, then you can delete the generated migration and regenerate it later, if needed.

## Motivation

Writing a safe migration can be daunting. Numerous articles have been written on the topic and a few gems are trying to address the problem. Even for someone who has a pretty good command of PostgreSQL, remembering all the subtleties of explicit locking can be problematic.

**Online Migrations** was created to catch dangerous operations and provide a guidance and code helpers to run them safely.

An operation is classified as dangerous if it either:

- Blocks reads or writes for more than a few seconds (after a lock is acquired)
- Has a good chance of causing application errors

## Example

Consider the following migration:

```ruby
class AddAdminToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :admin, :boolean, default: false, null: false
  end
end
```

If the `users` table is large, running this migration on a live PostgreSQL < 11 database will likely cause downtime.

A safer approach would be to run something like the following:

```ruby
class AddAdminToUsers < ActiveRecord::Migration[7.0]
  # Do not wrap the migration in a transaction so that locks are held for a shorter time.
  disable_ddl_transaction!

  def change
    # Lower PostgreSQL's lock timeout to avoid statement queueing.
    execute "SET lock_timeout TO '5s'" # The lock_timeout duration is customizable.

    # Add the column without the default value and the not-null constraint.
    add_column :users, :admin, :boolean

    # Set the column's default value.
    change_column_default :users, :admin, false

    # Backfill the column in batches.
    User.in_batches.update_all(admin: false)

    # Add the not-null constraint. Beforehand, set a short statement timeout so that
    # Postgres does not spend too much time performing the full table scan to verify
    # the column contains no nulls.
    execute "SET statement_timeout TO '5s'"
    change_column_null :users, :admin, false
  end
end
```

When you actually run the original migration, you will get an error message:

```txt
⚠️  [online_migrations] Dangerous operation detected ⚠️

Adding a column with a non-null default blocks reads and writes while the entire table is rewritten.

A safer approach is to:
1. add the column without a default value
2. change the column default
3. backfill existing rows with the new value
4. add the NOT NULL constraint

add_column_with_default takes care of all this steps:

class AddAdminToUsers < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_column_with_default :users, :admin, :boolean, default: false, null: false
  end
end
```

It suggests how to safely implement a migration, which essentially runs the steps similar to described in the previous example.

## Checks

Potentially dangerous operations:

- [removing a column](#removing-a-column)
- [adding a column with a default value](#adding-a-column-with-a-default-value)
- [backfilling data](#backfilling-data)
- [changing the type of a column](#changing-the-type-of-a-column)
- [renaming a column](#renaming-a-column)
- [renaming a table](#renaming-a-table)
- [creating a table with the force option](#creating-a-table-with-the-force-option)
- [adding a check constraint](#adding-a-check-constraint)
- [setting NOT NULL on an existing column](#setting-not-null-on-an-existing-column)
- [executing SQL directly](#executing-SQL-directly)
- [adding an index non-concurrently](#adding-an-index-non-concurrently)
- [removing an index non-concurrently](#removing-an-index-non-concurrently)
- [replacing an index](#replacing-an-index)
- [adding a reference](#adding-a-reference)
- [adding a foreign key](#adding-a-foreign-key)
- [adding a json column](#adding-a-json-column)
- [using primary key with short integer type](#using-primary-key-with-short-integer-type)
- [hash indexes](#hash-indexes)
- [adding multiple foreign keys](#adding-multiple-foreign-keys)

You can also add [custom checks](#custom-checks) or [disable specific checks](#disable-checks).

### Removing a column

:x: **Bad**

ActiveRecord caches database columns at runtime, so if you drop a column, it can cause exceptions until your app reboots.

```ruby
class RemoveNameFromUsers < ActiveRecord::Migration[7.0]
  def change
    remove_column :users, :name
  end
end
```

:white_check_mark: **Good**

1. Ignore the column:

  ```ruby
  # For Active Record 5+
  class User < ApplicationRecord
    self.ignored_columns = ["name"]
  end

  # For Active Record < 5
  class User < ActiveRecord::Base
    def self.columns
      super.reject { |c| c.name == "name" }
    end
  end
  ```

2. Deploy
3. Wrap column removing in a `safety_assured` block:

  ```ruby
  class RemoveNameFromUsers < ActiveRecord::Migration[7.0]
    def change
      safety_assured { remove_column :users, :name }
    end
  end
  ```

4. Remove column ignoring from `User` model
5. Deploy

### Adding a column with a default value

:x: **Bad**

In earlier versions of PostgreSQL adding a column with a non-null default value to an existing table blocks reads and writes while the entire table is rewritten.

```ruby
class AddAdminToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :admin, :boolean, default: false
  end
end
```

In PostgreSQL 11+ this no longer requires a table rewrite and is safe. Volatile expressions, however, such as `random()`, will still result in table rewrites.

:white_check_mark: **Good**

A safer approach is to:

1. add the column without a default value
2. change the column default
3. backfill existing rows with the new value

`add_column_with_default` helper takes care of all this steps:

```ruby
class AddAdminToUsers < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_column_with_default :users, :admin, :boolean, default: false
  end
end
```

**Note**: If you forget `disable_ddl_transaction!`, the migration will fail.

### Backfilling data

:x: **Bad**

ActiveRecord wraps each migration in a transaction, and backfilling in the same transaction that alters a table keeps the table locked for the [duration of the backfill](https://wework.github.io/data/2015/11/05/add-columns-with-default-values-to-large-tables-in-rails-postgres/).

```ruby
class AddAdminToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :admin, :boolean
    User.update_all(admin: false)
  end
end
```

Also, running a single query to update data can cause issues for large tables.

:white_check_mark: **Good**

There are three keys to backfilling safely: batching, throttling, and running it outside a transaction. Use a `update_column_in_batches` helper in a separate migration with `disable_ddl_transaction!`.

```ruby
class AddAdminToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :admin, :boolean
  end
end

class BackfillUsersAdminColumn < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def up
    update_column_in_batches(:users, :admin, false, pause_ms: 10)
  end
end
```

**Note**: If you forget `disable_ddl_transaction!`, the migration will fail.
**Note**: You may consider [background migrations](#background-migrations) to run data changes on large tables.

### Changing the type of a column

:x: **Bad**

Changing the type of an existing column blocks reads and writes while the entire table is rewritten.

```ruby
class ChangeFilesSizeType < ActiveRecord::Migration[7.0]
  def change
    change_column :files, :size, :bigint
  end
end
```

A few changes don't require a table rewrite (and are safe) in PostgreSQL:

- Increasing the length limit of a `varchar` column (or removing the limit)
- Changing a `varchar` column to a `text` column
- Changing a `text` column to a `varchar` column with no length limit
- Increasing the precision of a `decimal` or `numeric` column
- Making a `decimal` or `numeric` column unconstrained
- Changing between `timestamp` and `timestamptz` columns when session time zone is UTC in PostgreSQL 12+

:white_check_mark: **Good**

**Note**: The following steps can also be used to change the primary key's type (e.g., from `integer` to `bigint`).

A safer approach can be accomplished in several steps:

1. Create a new column and keep column's data in sync:

  ```ruby
  class InitializeChangeFilesSizeType < ActiveRecord::Migration[7.0]
    def change
      initialize_column_type_change :files, :size, :bigint
    end
  end
  ```

2. Backfill data from the old column to the new column:

  ```ruby
  class BackfillChangeFilesSizeType < ActiveRecord::Migration[7.0]
    disable_ddl_transaction!

    def up
      backfill_column_for_type_change :files, :size
    end

    def down
      # no op
    end
  end
  ```

3. Copy indexes, foreign keys, check constraints, NOT NULL constraint, swap new column in place:

  ```ruby
  class FinalizeChangeFilesSizeType < ActiveRecord::Migration[7.0]
    disable_ddl_transaction!

    def change
      finalize_column_type_change :files, :size
    end
  end
  ```

4. Deploy
5. Finally, if everything is working as expected, remove copy trigger and old column:

  ```ruby
  class CleanupChangeFilesSizeType < ActiveRecord::Migration[7.0]
    def up
      cleanup_change_column_type_concurrently :files, :size
    end

    def down
      initialize_column_type_change :files, :size, :integer
    end
  end
  ```

6. Deploy

### Renaming a column

:x: **Bad**

Renaming a column that's in use will cause errors in your application.

```ruby
class RenameUsersNameToFirstName < ActiveRecord::Migration[7.0]
  def change
    rename_column :users, :name, :first_name
  end
end
```

:white_check_mark: **Good**

The "classic" approach suggests creating a new column and copy data/indexes/etc to it from the old column. This can be costly for very large tables. There is a trick that helps to avoid such heavy operations.

The technique is built on top of database views, using the following steps:

1. Rename the table to some temporary name
2. Create a VIEW using the old table name with addition of a new column as an alias of the old one
3. Add a workaround for ActiveRecord's schema cache

For the previous example, to rename `name` column to `first_name` of the `users` table, we can run:

```sql
BEGIN;
ALTER TABLE users RENAME TO users_column_rename;
CREATE VIEW users AS SELECT *, first_name AS name FROM users;
COMMIT;
```

As database views do not expose the underlying table schema (default values, not null constraints, indexes, etc), further steps are needed to update the application to use the new table name. ActiveRecord heavily relies on this data, for example, to initialize new models.

To work around this limitation, we need to tell ActiveRecord to acquire this information from original table using the new table name.

**Online Migrations** provides several helpers to implement column renaming:

1. Instruct Rails that you are going to rename a column:

```ruby
OnlineMigrations.config.column_renames = {
  "users" => {
    "name" => "first_name"
  }
}
```

2. Deploy
3. Create a VIEW with aliased column:

```ruby
class InitializeRenameUsersNameToFirstName < ActiveRecord::Migration[7.0]
  def change
    initialize_column_rename :users, :name, :first_name
  end
end
```

4. Replace usages of the old column with a new column in the codebase
5. Deploy
6. Remove the column rename config from step 1
7. Remove the VIEW created in step 3:

```ruby
class FinalizeRenameUsersNameToFirstName < ActiveRecord::Migration[7.0]
  def change
    finalize_column_rename :users, :name, :first_name
  end
end
```

8. Deploy

### Renaming a table

:x: **Bad**

Renaming a table that's in use will cause errors in your application.

```ruby
class RenameClientsToUsers < ActiveRecord::Migration[7.0]
  def change
    rename_table :clients, :users
  end
end
```

:white_check_mark: **Good**

The "classic" approach suggests creating a new table and copy data/indexes/etc to it from the old table. This can be costly for very large tables. There is a trick that helps to avoid such heavy operations.

The technique is built on top of database views, using the following steps:

1. Rename the database table
2. Create a VIEW using the old table name by pointing to the new table name
3. Add a workaround for ActiveRecord's schema cache

For the previous example, to rename `name` column to `first_name` of the `users` table, we can run:

```sql
BEGIN;
ALTER TABLE clients RENAME TO users;
CREATE VIEW clients AS SELECT * FROM users;
COMMIT;
```

As database views do not expose the underlying table schema (default values, not null constraints, indexes, etc), further steps are needed to update the application to use the new table name. ActiveRecord heavily relies on this data, for example, to initialize new models.

To work around this limitation, we need to tell ActiveRecord to acquire this information from original table using the new table name.

**Online Migrations** provides several helpers to implement table renaming:

1. Instruct Rails that you are going to rename a table:

```ruby
OnlineMigrations.config.table_renames = {
  "clients" => "users"
}
```

2. Deploy
3. Create a VIEW:

```ruby
class InitializeRenameClientsToUsers < ActiveRecord::Migration[7.0]
  def change
    initialize_table_rename :clients, :users
  end
end
```

4. Replace usages of the old table with a new table in the codebase
5. Remove the table rename config from step 1
6. Deploy
7. Remove the VIEW created in step 3:

```ruby
class FinalizeRenameClientsToUsers < ActiveRecord::Migration[7.0]
  def change
    finalize_table_rename :clients, :users
  end
end
```

8. Deploy

### Creating a table with the force option

:x: **Bad**

The `force` option can drop an existing table.

```ruby
class CreateUsers < ActiveRecord::Migration[7.0]
  def change
    create_table :users, force: true do |t|
      # ...
    end
  end
end
```

:white_check_mark: **Good**

Create tables without the `force` option.

```ruby
class CreateUsers < ActiveRecord::Migration[7.0]
  def change
    create_table :users do |t|
      # ...
    end
  end
end
```

If you intend to drop an existing table, run `drop_table` first.

### Adding a check constraint

:x: **Bad**

Adding a check constraint blocks reads and writes while every row is checked.

```ruby
class AddCheckConstraint < ActiveRecord::Migration[7.0]
  def change
    add_check_constraint :users, "char_length(name) >= 1", name: "name_check"
  end
end
```

:white_check_mark: **Good**

Add the check constraint without validating existing rows, and then validate them in a separate transaction:

```ruby
class AddCheckConstraint < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_check_constraint :users, "char_length(name) >= 1", name: "name_check", validate: false
    validate_check_constraint :users, name: "name_check"
  end
end
```

**Note**: If you forget `disable_ddl_transaction!`, the migration will fail.

### Setting NOT NULL on an existing column

:x: **Bad**

Setting `NOT NULL` on an existing column blocks reads and writes while every row is checked.

```ruby
class ChangeUsersNameNull < ActiveRecord::Migration[7.0]
  def change
    change_column_null :users, :name, false
  end
end
```

:white_check_mark: **Good**

Instead, add a check constraint and validate it in a separate transaction:

```ruby
class ChangeUsersNameNull < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_not_null_constraint :users, :name, name: "users_name_null", validate: false
    validate_not_null_constraint :users, :name, name: "users_name_null"
  end
end
```

**Note**: If you forget `disable_ddl_transaction!`, the migration will fail.

A `NOT NULL` check constraint is functionally equivalent to setting `NOT NULL` on the column (but it won't show up in `schema.rb` in Rails < 6.1). In PostgreSQL 12+, once the check constraint is validated, you can safely set `NOT NULL` on the column and drop the check constraint.

```ruby
class ChangeUsersNameNullDropCheck < ActiveRecord::Migration[7.0]
  def change
    # in PostgreSQL 12+, you can then safely set NOT NULL on the column
    change_column_null :users, :name, false
    remove_check_constraint :users, name: "users_name_null"
  end
end
```

### Executing SQL directly

Online Migrations does not support inspecting what happens inside an `execute` call, so cannot help you here. Make really sure that what you're doing is safe before proceeding, then wrap it in a `safety_assured { ... }` block:

```ruby
class ExecuteSQL < ActiveRecord::Migration[7.0]
  def change
    safety_assured { execute "..." }
  end
end
```

### Adding an index non-concurrently

:x: **Bad**

Adding an index non-concurrently blocks writes.

```ruby
class AddIndexOnUsersEmail < ActiveRecord::Migration[7.0]
  def change
    add_index :users, :email, unique: true
  end
end
```

:white_check_mark: **Good**

Add indexes concurrently.

```ruby
class AddIndexOnUsersEmail < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :users, :email, unique: true, algorithm: :concurrently
  end
end
```

**Note**: If you forget `disable_ddl_transaction!`, the migration will fail. Also, note that indexes on new tables (those created in the same migration) don't require this.

### Removing an index non-concurrently

:x: **Bad**

While actual removing of an index is usually fast, removing it non-concurrently tries to obtain an `ACCESS EXCLUSIVE` lock on the table, waiting for all existing queries to complete and blocking all the subsequent queries (even `SELECT`s) on that table until the lock is obtained and index is removed.

```ruby
class RemoveIndexOnUsersEmail < ActiveRecord::Migration[7.0]
  def change
    remove_index :users, :email
  end
end
```

:white_check_mark: **Good**

Remove indexes concurrently.

```ruby
class RemoveIndexOnUsersEmail < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    remove_index :users, :email, algorithm: :concurrently
  end
end
```

**Note**: If you forget `disable_ddl_transaction!`, the migration will fail.

### Replacing an index

:x: **Bad**

Removing an old index before replacing it with the new one might result in slow queries while building the new index.

```ruby
class AddIndexOnEmailAnd < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    remove_index :projects, :creator_id, algorithm: :concurrently
    add_index :projects, [:creator_id, :created_at], algorithm: :concurrently
  end
end
```

**Note**: If removed index is covered by any existing index, then it is safe to remove the index before replacing it with the new one.

:white_check_mark: **Good**

A safer approach is to create the new index and then delete the old one.

```ruby
class AddIndexOnEmailAnd < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :projects, [:creator_id, :created_at], algorithm: :concurrently
    remove_index :projects, :creator_id, algorithm: :concurrently
  end
end
```

### Adding a reference

:x: **Bad**

Rails adds an index non-concurrently to references by default, which blocks writes. Additionally, if `foreign_key` option (without `validate: false`) is provided, both tables are blocked while it is validated.

```ruby
class AddUserToProjects < ActiveRecord::Migration[7.0]
  def change
    add_reference :projects, :user, foreign_key: true
  end
end
```

:white_check_mark: **Good**

Make sure the index is added concurrently and the foreign key is added in a separate migration.
Or you can use `add_reference_concurrently` helper. It will create a reference and take care of safely adding index and/or foreign key.

```ruby
class AddUserToProjects < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_reference_concurrently :projects, :user
  end
end
```

**Note**: If you forget `disable_ddl_transaction!`, the migration will fail.

### Adding a foreign key

:x: **Bad**

Adding a foreign key blocks writes on both tables.

```ruby
class AddForeignKeyToProjectsUser < ActiveRecord::Migration[7.0]
  def change
    add_foreign_key :projects, :users
  end
end
```

or

```ruby
class AddReferenceToProjectsUser < ActiveRecord::Migration[7.0]
  def change
    add_reference :projects, :user, foreign_key: true
  end
end
```

:white_check_mark: **Good**

Add the foreign key without validating existing rows, and then validate them in a separate transaction.

```ruby
class AddForeignKeyToProjectsUser < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_foreign_key :projects, :users, validate: false
    validate_foreign_key :projects, :users
  end
end
```

**Note**: If you forget `disable_ddl_transaction!`, the migration will fail.

### Adding a json column

:x: **Bad**

There's no equality operator for the `json` column type, which can cause errors for existing `SELECT DISTINCT` queries in your application.

```ruby
class AddSettingsToProjects < ActiveRecord::Migration[7.0]
  def change
    add_column :projects, :settings, :json
  end
end
```

:white_check_mark: **Good**

Use `jsonb` instead.

```ruby
class AddSettingsToProjects < ActiveRecord::Migration[7.0]
  def change
    add_column :projects, :settings, :jsonb
  end
end
```

### Using primary key with short integer type

:x: **Bad**

When using short integer types as primary key types, [there is a risk](https://m.signalvnoise.com/update-on-basecamp-3-being-stuck-in-read-only-as-of-nov-8-922am-cst/) of running out of IDs on inserts. The default type in ActiveRecord < 5.1 for primary and foreign keys is `INTEGER`, which allows a little over of 2 billion records. Active Record 5.1 changed the default type to `BIGINT`.

```ruby
class CreateUsers < ActiveRecord::Migration[7.0]
  def change
    create_table :users, id: :integer do |t|
      # ...
    end
  end
end
```

:white_check_mark: **Good**

Use one of `bigint`, `bigserial`, `uuid` instead.

```ruby
class CreateUsers < ActiveRecord::Migration[7.0]
  def change
    create_table :users, id: :bigint do |t| # bigint is the default for Active Record >= 5.1
      # ...
    end
  end
end
```

### Hash indexes

:x: **Bad - PostgreSQL < 10**

Hash index operations are not WAL-logged, so hash indexes might need to be rebuilt with `REINDEX` after a database crash if there were unwritten changes. Also, changes to hash indexes are not replicated over streaming or file-based replication after the initial base backup, so they give wrong answers to queries that subsequently use them. For these reasons, hash index use is discouraged.

```ruby
class AddIndexToUsersOnEmail < ActiveRecord::Migration[7.0]
  def change
    add_index :users, :email, unique: true, using: :hash
  end
end
```

:white_check_mark: **Good - PostgreSQL < 10**

Use B-tree indexes instead.

```ruby
class AddIndexToUsersOnEmail < ActiveRecord::Migration[7.0]
  def change
    add_index :users, :email, unique: true # B-tree by default
  end
end
```

### Adding multiple foreign keys

:x: **Bad**

Adding multiple foreign keys in a single migration blocks writes on all involved tables until migration is completed.
Avoid adding foreign key more than once per migration file, unless the source and target tables are identical.

```ruby
class CreateUserProjects < ActiveRecord::Migration[7.0]
  def change
    create_table :user_projects do |t|
      t.belongs_to :user, foreign_key: true
      t.belongs_to :project, foreign_key: true
    end
  end
end
```

:white_check_mark: **Good**

Add additional foreign keys in separate migration files. See [adding a foreign key](#adding-a-foreign-key) for how to properly add foreign keys.

```ruby
class CreateUserProjects < ActiveRecord::Migration[7.0]
  def change
    create_table :user_projects do |t|
      t.belongs_to :user, foreign_key: true
      t.belongs_to :project, foreign_key: false
    end
  end
end

class AddForeignKeyFromUserProjectsToProject < ActiveRecord::Migration[7.0]
  def change
    add_foreign_key :user_projects, :projects
  end
end
```

## Assuring Safety

To mark a step in the migration as safe, despite using a method that might otherwise be dangerous, wrap it in a `safety_assured` block.

```ruby
class MySafeMigration < ActiveRecord::Migration[7.0]
  def change
    safety_assured { remove_column :users, :some_column }
  end
end
```

Certain methods like `execute` and `change_table` cannot be inspected and are prevented from running by default. Make sure what you're doing is really safe and use this pattern.

## Configuring the gem

There are a few configurable options for the gem. Custom configurations should be placed in a `online_migrations.rb` initializer.

```ruby
OnlineMigrations.configure do |config|
  # ...
end
```

**Note**: Check the [source code](https://github.com/fatkodima/online_migrations/blob/master/lib/online_migrations/config.rb) for the list of all available configuration options.

### Custom checks

Add your own custom checks with:

```ruby
# config/initializers/online_migrations.rb

config.add_check do |method, args|
  if method == :add_column && args[0].to_s == "users"
    stop!("No more columns on the users table")
  end
end
```

Use the `stop!` method to stop migrations.

**Note**: Since `remove_column`, `execute` and `change_table` always require a `safety_assured` block, it's not possible to add a custom check for these operations.

### Disable Checks

Disable specific checks with:

```ruby
# config/initializers/online_migrations.rb

config.disable_check(:remove_index)
```

Check the [source code](https://github.com/fatkodima/online_migrations/blob/master/lib/online_migrations/error_messages.rb) for the list of keys.

### Down Migrations / Rollbacks

By default, checks are disabled when migrating down. Enable them with:

```ruby
# config/initializers/online_migrations.rb

config.check_down = true
```

### Custom Messages

You can customize specific error messages:

```ruby
# config/initializers/online_migrations.rb

config.error_messages[:add_column_default] = "Your custom instructions"
```

Check the [source code](https://github.com/fatkodima/online_migrations/blob/master/lib/online_migrations/error_messages.rb) for the list of keys.

### Migration Timeouts

It’s extremely important to set a short lock timeout for migrations. This way, if a migration can't acquire a lock in a timely manner, other statements won't be stuck behind it.

Add timeouts to `config/database.yml`:

```yml
production:
  connect_timeout: 5
  variables:
    lock_timeout: 10s
    statement_timeout: 15s
```

Or set the timeouts directly on the database user that runs migrations:

```sql
ALTER ROLE myuser SET lock_timeout = '10s';
ALTER ROLE myuser SET statement_timeout = '15s';
```

### Lock Timeout Retries

You can configure this gem to automatically retry statements that exceed the lock timeout:

```ruby
# config/initializers/online_migrations.rb

config.lock_retrier = OnlineMigrations::ExponentialLockRetrier.new(
  attempts: 30,                # attempt 30 retries
  base_delay: 0.01.seconds,    # starting with delay of 10ms between each unsuccessful try, increasing exponentially
  max_delay: 1.minute,         # maximum delay is 1 minute
  lock_timeout: 0.05.seconds   # and 50ms set as lock timeout for each try
)
```

When statement within transaction fails - the whole transaction is retried.

To permanently disable lock retries, you can set `lock_retrier` to `nil`.
To temporarily disable lock retries while running migrations, set `DISABLE_LOCK_RETRIES` env variable.

**Note**: Statements are retried by default, unless lock retries are disabled. It is possible to implement more sophisticated lock retriers. See [source code](https://github.com/fatkodima/online_migrations/blob/master/lib/online_migrations/lock_retrier.rb) for the examples.

### Existing Migrations

To mark migrations as safe that were created before installing this gem, configure the migration version starting after which checks are performed:

```ruby
# config/initializers/online_migrations.rb

config.start_after = 20220101000000
```

Use the version from your latest migration.

### Target Version

If your development database version is different from production, you can specify the production version so the right checks run in development.

```ruby
# config/initializers/online_migrations.rb

config.target_version = 10 # or "12.9" etc
```

For safety, this option only affects development and test environments. In other environments, the actual server version is always used.

### Small Tables

Most projects have tables that are known to be small in size. These are usually "settings", "prices", "plans" etc. It is considered safe to perform most of the dangerous operations on them, like adding indexes, columns etc.

To mark tables as small:

```ruby
config.small_tables = [:settings, :prices]
```

## Background Migrations

Read [BACKGROUND_MIGRATIONS.md](BACKGROUND_MIGRATIONS.md) on how to perform data migrations on large tables.

## Credits

Thanks to [strong_migrations gem](https://github.com/ankane/strong_migrations), [GitLab](https://gitlab.com/gitlab-org/gitlab) and [maintenance_tasks gem](https://github.com/Shopify/maintenance_tasks) for the original ideas.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/fatkodima/online_migrations.

## Development

After checking out the repo, run `bundle install` to install dependencies. Run `createdb online_migrations_test` to create a test database. Then, run `bundle exec rake test` to run the tests. This project uses multiple Gemfiles to test against multiple versions of ActiveRecord; you can run the tests against the specific version with `BUNDLE_GEMFILE=gemfiles/activerecord_61.gemfile bundle exec rake test`.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Additional resources

Alternatives:

- https://github.com/ankane/strong_migrations
- https://github.com/LendingHome/zero_downtime_migrations
- https://github.com/braintree/pg_ha_migrations
- https://github.com/doctolib/safe-pg-migrations

Interesting reads:

- [Explicit Locking](https://www.postgresql.org/docs/current/explicit-locking.html)
- [When Postgres blocks: 7 tips for dealing with locks](https://www.citusdata.com/blog/2018/02/22/seven-tips-for-dealing-with-postgres-locks/)
- [PostgreSQL rocks, except when it blocks: Understanding locks](https://www.citusdata.com/blog/2018/02/15/when-postgresql-blocks/)
- [PostgreSQL at Scale: Database Schema Changes Without Downtime](https://medium.com/paypal-tech/postgresql-at-scale-database-schema-changes-without-downtime-20d3749ed680)
- [Adding a NOT NULL CONSTRAINT on PG Faster with Minimal Locking](https://medium.com/doctolib-engineering/adding-a-not-null-constraint-on-pg-faster-with-minimal-locking-38b2c00c4d1c)
- [Adding columns with default values to really large tables in Postgres + Rails](https://wework.github.io/data/2015/11/05/add-columns-with-default-values-to-large-tables-in-rails-postgres/)
- [Safe Operations For High Volume PostgreSQL](https://www.braintreepayments.com/blog/safe-operations-for-high-volume-postgresql/)
- [Stop worrying about PostgreSQL locks in your Rails migrations](https://medium.com/doctolib/stop-worrying-about-postgresql-locks-in-your-rails-migrations-3426027e9cc9)
- [Avoiding integer overflows with zero downtime](https://buildkite.com/blog/avoiding-integer-overflows-with-zero-downtime)

## Maybe TODO

- support MySQL
- support other ORMs

Background migrations:

- extract as a separate gem
- add UI
- support batching over non-integer and multiple columns

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
