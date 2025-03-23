# Background Schema Migrations

When a project grows, your database starts to be heavy and performing schema changes through the deployment process can be very painful.

E.g., for very large tables, index creation can be a challenge to manage. While adding indexes `CONCURRENTLY` creates indexes in a way that does not block ordinary traffic, it can still be problematic when index creation runs for many hours. Necessary database operations like autovacuum cannot run, and the deployment process is usually blocked waiting for index creation to finish.

**Note**: You probably don't need to use this feature for smaller projects, since performing schema changes directly on smaller databases will be perfectly fine and will not block the deployment too much.

## Installation

Make sure you have migration files generated when installed this gem:

```sh
$ bin/rails generate online_migrations:install
```

Start a background migrations scheduler. For example, to run it on cron using [whenever gem](https://github.com/javan/whenever) add the following lines to its `schedule.rb` file:

```ruby
every 1.minute do
  runner "OnlineMigrations.run_background_schema_migrations"
end
```

or run it manually when the deployment is finished, from the rails console:

```rb
[production] (main)> OnlineMigrations.run_background_schema_migrations
```

**Note**: Scheduler will perform only one migration at a time, to not load the database too much. If you enqueued multiple migrations or a migration for multiple shards, you need to call this method a few times.

**Note**: Make sure that the process that runs the scheduler does not die until the migration is finished.

## Enqueueing a Background Schema Migration

Currently, only helpers for adding/removing indexes and validating constraints are provided.

Background schema migrations should be performed in 2 steps (e.g. for index creation):

1. Create a PR that schedules the index to be created
2. Verify that the PR was deployed and that the index was actually created on production.
  Create a follow-up PR with a regular migration that creates an index synchronously (will be a no op when run on production) and commit the schema changes for `schema.rb`/`structure.sql`

To schedule an index creation:

```ruby
add_index_in_background(:users, :email, unique: true)
```

To schedule an index removal:

```ruby
remove_index_in_background(:users, name: "index_users_on_email")
```

To schedule a foreign key validation:

```ruby
validate_foreign_key_in_background(:users, :companies)
```

To schedule a constraint (`CHECK` constraint, `FOREIGN KEY` constraint) validation:

```ruby
validate_constraint_in_background(:users, "first_name_not_null")
```

All the helpers accept additional configuration options which controls how the background schema migration is run. Check the [source code](https://github.com/fatkodima/online_migrations/blob/master/lib/online_migrations/background_schema_migrations/migration_helpers.rb) for the list of all available configuration options.

## Depending on schema changes

You shouldn't depend on the schema until the background schema migration is finished. If having the schema migrated is a requirement, then the `ensure_background_schema_migration_succeeded` helper can be used to guarantee that the migration succeeded and the schema change applied.

## Retrying a failed migration

To retry a failed migration, run:

```ruby
migration = OnlineMigrations::BackgroundSchemaMigrations::Migration.find(id)
migration.retry # => `true` if scheduled to be retried, `false` - if not
```

The migration will be retried on the next Scheduler run.

## Cancelling a migration

To cancel an existing migration from future performing, run:

```ruby
migration = OnlineMigrations::BackgroundSchemaMigrations::Migration.find(id)
migration.cancel
```

## Instrumentation

Background schema migrations use the [ActiveSupport::Notifications](http://api.rubyonrails.org/classes/ActiveSupport/Notifications.html) API.

You can subscribe to `background_schema_migrations` events and log it, graph it, etc.

To get notified about specific type of events, subscribe to the event name followed by the `background_schema_migrations` namespace. E.g. for retries use:

```ruby
# config/initializers/online_migrations.rb
ActiveSupport::Notifications.subscribe("retried.background_schema_migrations") do |name, start, finish, id, payload|
  # background schema migration object is available in payload[:migration]

  # Your code here
end
```

If you want to subscribe to every `background_schema_migrations` event, use:

```ruby
# config/initializers/online_migrations.rb
ActiveSupport::Notifications.subscribe(/background_schema_migrations/) do |name, start, finish, id, payload|
  # background schema migration object is available in payload[:migration]

  # Your code here
end
```

Available events:

* `started.background_schema_migrations`
* `run.background_schema_migrations`
* `completed.background_schema_migrations`
* `retried.background_schema_migrations`
* `throttled.background_schema_migrations`

## Monitoring Background Schema Migrations

Background Schema Migrations can be in various states during its execution:

* **enqueued**: A migration has been enqueued by the user.
* **running**: A migration is being performed by a migration executor.
* **errored**: A migration raised an error during last run.
* **failed**: A migration raises an error when running and retry attempts exceeded.
* **succeeded**: A migration finished without error.
* **cancelled**: A migration was cancelled by the user.

## Configuring

There are a few configurable options for the Background Schema Migrations. Custom configurations should be placed in a `online_migrations.rb` initializer.

Check the [source code](https://github.com/fatkodima/online_migrations/blob/master/lib/online_migrations/background_schema_migrations/config.rb) for the list of all available configuration options.

**Note**: You can dynamically change certain migration parameters while the migration is run.
For example,
```ruby
migration = OnlineMigrations::BackgroundSchemaMigrations::Migration.find(id)
migration.update!(
  statement_timeout: 2.hours,  # The statement timeout value used when running the migration
  max_attempts: 10             # The # of attempts the failing migration will be retried
)
```

### Customizing the error handler

Exceptions raised while a Background Schema Migration is performing are rescued and information about the error is persisted in the database.

If you want to integrate with an exception monitoring service (e.g. Bugsnag), you can define an error handler:

```ruby
# config/initializers/online_migrations.rb

OnlineMigrations.config.background_schema_migrations.error_handler = ->(error, errored_migration) do
  Bugsnag.notify(error) do |notification|
    notification.add_metadata(:background_schema_migration, { name: errored_migration.name })
  end
end
```

The error handler should be a lambda that accepts 2 arguments:

* `error`: The exception that was raised.
* `errored_migration`: An `OnlineMigrations::BackgroundSchemaMigrations::Migration` object that represents a failed migration.

### Multiple databases and sharding

If you have multiple databases or sharding, you may need to configure where background migrations related tables live
by configuring the parent model:

```ruby
# config/initializers/online_migrations.rb

# Referring to one of the databases
OnlineMigrations::ApplicationRecord.connects_to database: { writing: :animals }

# Referring to one of the shards (via `:database` option)
OnlineMigrations::ApplicationRecord.connects_to database: { writing: :shard_one }
```

By default, ActiveRecord uses the database config named `:primary` (if exists) under the environment section from the `database.yml`.
Otherwise, the first config under the environment section is used.

By default, the scheduler works on a single shard on each run. To run a separate scheduler per shard:

```ruby
[:shard_one, :shard_two, :shard_three].each do |shard|
  every 1.minute do
    runner "OnlineMigrations.run_background_schema_migrations(shard: :#{shard})"
  end
end
```
