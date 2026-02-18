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

## Requiring safety_assured reason

To require safety reason explanation when calling `safety_assured` (disabled by default):

```ruby
config.require_safety_assured_reason = true
```

## Down Migrations / Rollbacks

By default, checks are disabled when migrating down. Enable them with:

```ruby
config.check_down = true
```

## Custom Messages

You can customize specific error messages:

```ruby
config.error_messages[:add_column_with_default] = "Your custom instructions"
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

When a statement within transaction fails - the whole transaction is retried. If any statement fails when running outside a transaction (e.g. using `disable_ddl_transaction!`) then only that statement is retried.

**Note**: Statements are retried by default, unless lock retries are disabled. It is possible to implement more sophisticated lock retriers. See [source code](https://github.com/fatkodima/online_migrations/blob/master/lib/online_migrations/lock_retrier.rb) for the examples.

### Command-specific lock retry configuration

For migrations using `disable_ddl_transaction!`, you can implement command-specific lock retry behavior. This is useful when different DDL operations have different locking characteristics:

- `add_index` with `algorithm: :concurrently` uses `ShareUpdateExclusiveLock` (less restrictive), so can use longer timeouts
- `add_foreign_key` uses `AccessExclusiveLock` (blocks all access), so should use shorter timeouts to fail fast

**Note**: Command-specific configuration only works for migrations with `disable_ddl_transaction!`. For migrations running within transactions (the default), the lock retrier wraps the entire transaction and doesn't have visibility into individual DDL commands.

```ruby
module OnlineMigrations
  class CommandAwareLockRetrier < LockRetrier
    # You can vary the number of attempts based on the command
    def attempts(command = nil, arguments = [])
      case command
      when :add_index
        # Concurrent index creation uses longer individual timeouts,
        # so fewer attempts are needed to reach the same overall window
        10
      when :add_foreign_key
        # Foreign keys use shorter timeouts to fail fast,
        # so more attempts are needed to reach the same overall window
        60
      else
        # Default attempts for other operations
        30
      end
    end

    def lock_timeout(attempt, command = nil, arguments = [])
      case command
      when :add_index
        # Concurrent index creation is less restrictive, use longer timeout
        30.seconds
      when :add_foreign_key
        # Foreign keys block all access, use shorter timeout to fail fast
        5.seconds
      else
        # Default timeout for other operations
        10.seconds
      end
    end

    def delay(attempt, command = nil, arguments = [])
      case command
      when :add_index
        # Longer delay for index operations since they take time anyway
        3.seconds
      when :add_foreign_key
        # Shorter delay to retry faster for quick FK operations
        1.second
      else
        # Default delay for other operations
        2.seconds
      end
    end
  end
end

config.lock_retrier = OnlineMigrations::CommandAwareLockRetrier.new
```

All three methods (`attempts`, `lock_timeout`, and `delay`) can receive command-specific parameters:
- `command` - the migration method being called (e.g., `:add_index`, `:add_column`, `:add_foreign_key`), or `nil` for transaction-wrapped migrations
- `arguments` - an array of arguments passed to the migration method

Additionally, `lock_timeout` and `delay` receive:
- `attempt` - the current retry attempt number (1-indexed)

This allows you to fine-tune the retry strategy for different commands. For example, to maintain roughly the same total timeout window:
- `add_index`: 10 attempts × (30s lock + 3s delay) = ~5.5 minute window
- `add_foreign_key`: 60 attempts × (5s lock + 1s delay) = ~6 minute window

#### Alternative: Configuration Hash Approach

For simpler use cases, you can use a configuration hash instead of case statements:

```ruby
module OnlineMigrations
  class ConfigurableLockRetrier < LockRetrier
    COMMAND_CONFIGS = {
      add_index: {
        attempts: 10,
        lock_timeout: 30.seconds,
        delay: 3.seconds
      },
      add_foreign_key: {
        attempts: 60,
        lock_timeout: 5.seconds,
        delay: 1.second
      },
      default: {
        attempts: 30,
        lock_timeout: 10.seconds,
        delay: 2.seconds
      }
    }

    def attempts(command = nil, arguments = [])
      config_for(command)[:attempts]
    end

    def lock_timeout(attempt, command = nil, arguments = [])
      config_for(command)[:lock_timeout]
    end

    def delay(attempt, command = nil, arguments = [])
      config_for(command)[:delay]
    end

    private

    def config_for(command)
      COMMAND_CONFIGS[command] || COMMAND_CONFIGS[:default]
    end
  end
end

config.lock_retrier = OnlineMigrations::ConfigurableLockRetrier.new
```

This approach is more concise and easier to maintain when you have simple static configurations per command. The case statement approach (shown above) is better when you need conditional logic or want to use the `attempt` parameter dynamically.

To temporarily disable lock retries while running migrations, set `DISABLE_LOCK_RETRIES` env variable. This is useful when you are deploying a hotfix and do not want to wait too long while the lock retrier safely tries to acquire the lock, but try to acquire the lock immediately with the default configured lock timeout value.

To permanently disable lock retries, you can set `lock_retrier` to `nil`.

Finally, if your lock retrier implementation does not have an explicit `lock_timeout` value configured, then the timeout behavior will fallback to the database configuration (`config/database.yml`) or the PostgreSQL server config value ([off by default](https://www.postgresql.org/docs/current/runtime-config-client.html#GUC-LOCK-TIMEOUT)). Take care configuring this value, as this fallback may result in your migrations running without a lock timeout!

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
class AddAdminToUsers < ActiveRecord::Migration[8.0]
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

## Running background migrations inline

`config.run_background_migrations_inline` can be configured with a proc to decide whether background migrations should be run inline. For convenience defaults to true for development and test environments.

```ruby
# config/initializers/online_migrations.rb
config.run_background_migrations_inline = -> { Rails.env.local? }
```

Set to `nil` to avoid running background migrations inline.

## Throttling

Background data and schema migrations can be taxing on your database. There is a throttling mechanism that can be used to throttle a background migration when a given condition is met. If a migration is throttled, it will be interrupted and retried on the next Scheduler cycle run.

Specify the throttle condition as a block:

```ruby
# config/initializers/online_migrations.rb

OnlineMigrations.config.throttler = -> { DatabaseStatus.unhealthy? }
```

**Note**: It's up to you to define a throttling condition that makes sense for your app. For example, you can check various PostgreSQL metrics such as replication lag, DB threads, whether DB writes are available, etc.

## Customizing the backtrace cleaner

`OnlineMigrations.config.backtrace_cleaner` can be configured to specify a backtrace cleaner to use when a background data or schema migration errors and the backtrace is cleaned and persisted. An `ActiveSupport::BacktraceCleaner` should be used.

```ruby
# config/initializers/online_migrations.rb

cleaner = ActiveSupport::BacktraceCleaner.new
cleaner.add_silencer { |line| line =~ /ignore_this_dir/ }

OnlineMigrations.config.backtrace_cleaner = cleaner
```

If none is specified, the default `Rails.backtrace_cleaner` will be used to clean backtraces.

## Schema Sanity

Columns can flip order in `db/schema.rb` when you have multiple developers. One way to prevent this is to [alphabetize them](https://www.pgrs.net/2008/03/12/alphabetize-schema-rb-columns/).
To alphabetize columns:

```ruby
config.alphabetize_schema = true
```
