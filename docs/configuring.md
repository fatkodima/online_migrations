# Configuring

There are a few configurable options for the gem. Custom configurations should be placed in a `online_migrations.rb` initializer.

```ruby
# config/initializers/online_migrations.rb

OnlineMigrations.configure do |config|
  # ...
end
```

**Note**: Check the [source code](https://github.com/fatkodima/online_migrations/blob/master/lib/online_migrations/config.rb) for the list of all available configuration options.

## Custom checks

Add your own custom checks with:

```ruby
config.add_check do |method, args|
  if method == :add_column && args[0].to_s == "users"
    stop!("No more columns on the users table")
  end
end
```

Use the `stop!` method to stop migrations.

**Note**: Since `remove_column`, `execute` and `change_table` always require a `safety_assured` block, it's not possible to add a custom check for these operations.

## Disable Checks

Disable specific checks with:

```ruby
config.disable_check(:remove_index)
```

Check the [source code](https://github.com/fatkodima/online_migrations/blob/master/lib/online_migrations/error_messages.rb) for the list of keys.

## Down Migrations / Rollbacks

By default, checks are disabled when migrating down. Enable them with:

```ruby
config.check_down = true
```

## Custom Messages

You can customize specific error messages:

```ruby
config.error_messages[:add_column_default] = "Your custom instructions"
```

Check the [source code](https://github.com/fatkodima/online_migrations/blob/master/lib/online_migrations/error_messages.rb) for the list of keys.

## Migration Timeouts

It’s extremely important to set a short lock timeout for migrations. This way, if a migration can't acquire a lock in a timely manner, other statements won't be stuck behind it.
We also recommend setting a long statement timeout so migrations can run for a while.

You can configure a statement timeout for migrations via:

```ruby
config.statement_timeout = 1.hour
```

and a lock timeout for migrations can be configured via the `lock_retrier`.

**Note**: If you do not set a lock retrier the default `NullLockRetrier` is used and it has a `lock_timeout` value of `0` that [disables the timeout](https://www.postgresql.org/docs/16/runtime-config-client.html#GUC-LOCK-TIMEOUT).

Or set the timeouts directly on the database user that runs migrations:

```sql
ALTER ROLE myuser SET lock_timeout = '10s';
ALTER ROLE myuser SET statement_timeout = '1h';
```

## App Timeouts

We recommend adding timeouts to `config/database.yml` to prevent connections from hanging and individual queries from taking up too many resources in controllers, jobs, the Rails console, and other places.

```yml
production:
  connect_timeout: 5
  variables:
    lock_timeout: 10s
    statement_timeout: 15s
```

## Lock Timeout Retries

You can configure this gem to automatically retry statements that exceed the lock timeout:

```ruby
config.lock_retrier = OnlineMigrations::ExponentialLockRetrier.new(
  attempts: 30,                # attempt 30 retries
  base_delay: 0.01.seconds,    # starting with delay of 10ms between each unsuccessful try, increasing exponentially
  max_delay: 1.minute,         # maximum delay is 1 minute
  lock_timeout: 0.2.seconds    # and 200ms set as lock timeout for each try. Remove this line to use a default lock timeout.
)
```

When statement within transaction fails - the whole transaction is retried.

To permanently disable lock retries, you can set `lock_retrier` to `nil`.

To temporarily disable lock retries while running migrations, set `DISABLE_LOCK_RETRIES` env variable. This is useful when you are deploying a hotfix and do not want to wait too long while the lock retrier safely tries to acquire the lock, but try to acquire the lock immediately with the default configured lock timeout value.

**Note**: Statements are retried by default, unless lock retries are disabled. It is possible to implement more sophisticated lock retriers. See [source code](https://github.com/fatkodima/online_migrations/blob/master/lib/online_migrations/lock_retrier.rb) for the examples.

## Existing Migrations

To mark migrations as safe that were created before installing this gem, configure the migration version starting after which checks are performed:

```ruby
config.start_after = 20220101000000

# or if you use multiple databases (Active Record 6+)
config.start_after = { primary: 20211112000000, animals: 20220101000000 }
```

Use the version from your latest migration.

## Target Version

If your development database version is different from production, you can specify the production version so the right checks run in development.

```ruby
config.target_version = 10 # or "12.9" etc

# or if you use multiple databases (Active Record 6+)
config.target_version = { primary: 10, animals: 14.1 }
```

For safety, this option only affects development and test environments. In other environments, the actual server version is always used.

## Small Tables

Most projects have tables that are known to be small in size. These are usually "settings", "prices", "plans" etc. It is considered safe to perform most of the dangerous operations on them, like adding indexes, columns etc.

To mark tables as small:

```ruby
config.small_tables = [:settings, :prices]
```

## Verbose SQL logs

For any operation, **Online Migrations** can output the performed SQL queries.

This is useful to demystify `online_migrations` inner workings, and to better investigate migration failure in production. This is also useful in development to get a better grasp of what is going on for high-level statements like `add_column_with_default`.

Consider migration, running on PostgreSQL < 11:

```ruby
class AddAdminToUsers < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_column_with_default :users, :admin, :boolean, default: false
  end
end
```

Instead of the traditional output:

```
== 20220106214827 AddAdminToUsers: migrating ==================================
-- add_column_with_default(:users, :admin, :boolean, {:default=>false})
   -> 0.1423s
== 20220106214827 AddAdminToUsers: migrated (0.1462s) =========================
```

**Online Migrations** will output the following logs:

```
== 20220106214827 AddAdminToUsers: migrating ==================================
   (0.3ms)  SHOW lock_timeout
   (0.2ms)  SET lock_timeout TO '50ms'
-- add_column_with_default(:users, :admin, :boolean, {:default=>false})
  TRANSACTION (0.1ms)  BEGIN
   (37.7ms)  ALTER TABLE "users" ADD "admin" boolean DEFAULT NULL
   (0.5ms)  ALTER TABLE "users" ALTER COLUMN "admin" SET DEFAULT FALSE
  TRANSACTION (0.3ms)  COMMIT
   Load (0.3ms)  SELECT "users"."id" FROM "users" WHERE ("users"."admin" != FALSE OR "users"."admin" IS NULL) ORDER BY "users"."id" ASC LIMIT $1  [["LIMIT", 1]]
   Load (0.5ms)  SELECT "users"."id" FROM "users" WHERE ("users"."admin" != FALSE OR "users"."admin" IS NULL) AND "users"."id" >= 1 ORDER BY "users"."id" ASC LIMIT $1 OFFSET $2  [["LIMIT", 1], ["OFFSET", 1000]]
  #<Class:0x00007f8ae3703f08> Update All (9.6ms)  UPDATE "users" SET "admin" = $1 WHERE ("users"."admin" != FALSE OR "users"."admin" IS NULL) AND "users"."id" >= 1 AND "users"."id" < 1001  [["admin", false]]
   Load (0.8ms)  SELECT "users"."id" FROM "users" WHERE ("users"."admin" != FALSE OR "users"."admin" IS NULL) AND "users"."id" >= 1001 ORDER BY "users"."id" ASC LIMIT $1 OFFSET $2  [["LIMIT", 1], ["OFFSET", 1000]]
  #<Class:0x00007f8ae3703f08> Update All (1.5ms)  UPDATE "users" SET "admin" = $1 WHERE ("users"."admin" != FALSE OR "users"."admin" IS NULL) AND "users"."id" >= 1001  [["admin", false]]
   -> 0.1814s
   (0.4ms)  SET lock_timeout TO '5s'
== 20220106214827 AddAdminToUsers: migrated (0.1840s) =========================
```

So you can actually check which steps are performed.

**Note**: The `SHOW` statements are used by **Online Migrations** to query settings for their original values in order to restore them after the work is done.

To enable verbose sql logs:

```ruby
config.verbose_sql_logs = true
```

This feature is enabled by default in a staging and production Rails environments. You can override this setting via `ONLINE_MIGRATIONS_VERBOSE_SQL_LOGS` environment variable.

## Analyze Tables

Analyze tables automatically (to update planner statistics) after an index is added.
Add to an initializer file:

```ruby
config.auto_analyze = true
```

### Running background migrations inline

`config.run_background_migrations_inline` can be configured with a proc to decide whether background migrations should be run inline. For convenience defaults to true for development and test environments.

```ruby
# config/initializers/online_migrations.rb
config.run_background_migrations_inline = -> { Rails.env.local? }
```

Set to `nil` to avoid running background migrations inline.

## Schema Sanity

Columns can flip order in `db/schema.rb` when you have multiple developers. One way to prevent this is to [alphabetize them](https://www.pgrs.net/2008/03/12/alphabetize-schema-rb-columns/).
To alphabetize columns:

```ruby
config.alphabetize_schema = true
```
