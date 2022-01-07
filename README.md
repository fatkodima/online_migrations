# OnlineMigrations

Welcome to your new gem! In this directory, you'll find the files you need to be able to package up your Ruby library into a gem. Put your Ruby code in the file `lib/online_migrations`. To experiment with that code, run `bin/console` for an interactive prompt.

TODO: Delete this and the text above, and describe your gem

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'online_migrations'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install online_migrations

## Usage

TODO: Write usage instructions here

## Checks

Potentially dangerous operations:

- [removing a column](#removing-a-column)
- [adding a column with a default value](#adding-a-column-with-a-default-value)
- [backfilling data](#backfilling-data)
- [renaming a column](#renaming-a-column)
- [renaming a table](#renaming-a-table)
- [creating a table with the force option](#creating-a-table-with-the-force-option)
- [adding a check constraint](#adding-a-check-constraint)
- [setting NOT NULL on an existing column](#setting-not-null-on-an-existing-column)
- [executing SQL directly](#executing-SQL-directly)
- [adding an index non-concurrently](#adding-an-index-non-concurrently)
- [removing an index non-concurrently](#removing-an-index-non-concurrently)
- [adding a foreign key](#adding-a-foreign-key)
- [adding a json column](#adding-a-json-column)

### Removing a column

#### Bad

ActiveRecord caches database columns at runtime, so if you drop a column, it can cause exceptions until your app reboots.

```ruby
class RemoveNameFromUsers < ActiveRecord::Migration[7.0]
  def change
    remove_column :users, :name
  end
end
```

#### Good

1. Ignore the column:

  ```ruby
  class User < ApplicationRecord
    self.ignored_columns = ["name"]
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

#### Bad

In earlier versions of PostgreSQL adding a column with a non-null default value to an existing table blocks reads and writes while the entire table is rewritten.

```ruby
class AddAdminToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :admin, :boolean, default: false
  end
end
```

In PostgreSQL 11+ this no longer requires a table rewrite and is safe. Volatile expressions, however, such as `random()`, will still result in table rewrites.

#### Good

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

#### Bad

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

#### Good

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

## Renaming a column

#### Bad

Renaming a column that's in use will cause errors in your application.

```ruby
class RenameUsersNameToFirstName < ActiveRecord::Migration[7.0]
  def change
    rename_column :users, :name, :first_name
  end
end
```

#### Good

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

#### Bad

Renaming a table that's in use will cause errors in your application.

```ruby
class RenameClientsToUsers < ActiveRecord::Migration[7.0]
  def change
    rename_table :clients, :users
  end
end
```

#### Good

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

#### Bad

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

#### Good

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

#### Bad

Adding a check constraint blocks reads and writes while every row is checked.

```ruby
class AddCheckConstraint < ActiveRecord::Migration[7.0]
  def change
    add_check_constraint :users, "char_length(name) >= 1", name: "name_check"
  end
end
```

#### Good

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

#### Bad

Setting `NOT NULL` on an existing column blocks reads and writes while every row is checked.

```ruby
class ChangeUsersNameNull < ActiveRecord::Migration[7.0]
  def change
    change_column_null :users, :name, false
  end
end
```

#### Good

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

#### Bad

Adding an index non-concurrently blocks writes.

```ruby
class AddIndexOnUsersEmail < ActiveRecord::Migration[7.0]
  def change
    add_index :users, :email, unique: true
  end
end
```

#### Good

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

#### Bad

While actual removing of an index is usually fast, removing it non-concurrently tries to obtain an `ACCESS EXCLUSIVE` lock on the table, waiting for all existing queries to complete and blocking all the subsequent queries (even `SELECT`s) on that table until the lock is obtained and index is removed.

```ruby
class RemoveIndexOnUsersEmail < ActiveRecord::Migration[7.0]
  def change
    remove_index :users, :email
  end
end
```

#### Good

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

### Adding a foreign key

#### Bad

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

#### Good

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

#### Bad

There's no equality operator for the `json` column type, which can cause errors for existing `SELECT DISTINCT` queries in your application.

```ruby
class AddSettingsToProjects < ActiveRecord::Migration[7.0]
  def change
    add_column :projects, :settings, :json
  end
end
```

#### Good

Use `jsonb` instead.

```ruby
class AddSettingsToProjects < ActiveRecord::Migration[7.0]
  def change
    add_column :projects, :settings, :jsonb
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

### Down Migrations / Rollbacks

By default, checks are disabled when migrating down. Enable them with:

```ruby
# config/initializers/online_migrations.rb

config.check_down = true
```

### Target Version

If your development database version is different from production, you can specify the production version so the right checks run in development.

```ruby
# config/initializers/online_migrations.rb

config.target_version = 10 # or "12.9" etc
```

For safety, this option only affects development and test environments. In other environments, the actual server version is always used.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/online_migrations.


## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
