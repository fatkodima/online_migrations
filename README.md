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
- [creating a table with the force option](#creating-a-table-with-the-force-option)
- [adding a check constraint](#adding-a-check-constraint)
- [executing SQL directly](#executing-SQL-directly)
- [adding an index non-concurrently](#adding-an-index-non-concurrently)
- [removing an index non-concurrently](#removing-an-index-non-concurrently)
- [adding a foreign key](#adding-a-foreign-key)

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

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/online_migrations.


## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
