# Background Data Migrations

When a project grows, your database starts to be heavy and changing the data through the deployment process can be very painful.

Background migrations should be used to perform data migrations on large tables or when the migration will take a lot of time. For example, you can use background migrations to migrate data that’s stored in a single JSON column to a separate table instead or backfill some column's value from an API.

**Note**: You probably don't need to use background migrations for smaller projects, since updating data directly on smaller databases will be perfectly fine and will not block the deployment too much.

## Installation

Make sure you have migration files generated when installed this gem:

```sh
$ bin/rails generate online_migrations:install
```

Start a background migrations scheduler. For example, to run it on cron using [whenever gem](https://github.com/javan/whenever) add the following lines to its `schedule.rb` file:

```ruby
every 1.minute do
  runner "OnlineMigrations.run_background_data_migrations"
end
```

## Creating a Background Migration

A generator is provided to create background migrations. Generate a new background migration by running:

```bash
$ bin/rails generate online_migrations:background_migration backfill_project_issues_count
```

This creates the background migration file `lib/online_migrations/background_migrations/backfill_project_issues_count.rb`
and the regular migration file `db/migrate/xxxxxxxxxxxxxx_enqueue_backfill_project_issues_count.rb` where we enqueue it.

The generated class is a subclass of `OnlineMigrations::BackgroundMigration` that implements:

* `relation`: return an `ActiveRecord::Relation` to be iterated over
* `process_batch`: do the work of your background migration on a batch (`ActiveRecord::Relation`)
* `count`: return the number of rows that will be iterated over (optional, to be
  able to show progress)

Example:

```ruby
# lib/online_migrations/background_migrations/backfill_project_issues_count.rb

module OnlineMigrations
  module BackgroundMigrations
    class BackfillProjectIssuesCount < OnlineMigrations::BackgroundMigration
      class Project < ActiveRecord::Base; end

      def relation
        Project.all
      end

      def process_batch(projects)
        projects.update_all(<<~SQL)
          issues_count = (
            SELECT COUNT(*)
            FROM issues
            WHERE issues.project_id = projects.id
          )
        SQL
      end

      def count
        relation.count
      end
    end
  end
end
```

## Enqueueing a Background Migration

You can enqueue your background migration to be run by the scheduler via:

```ruby
# db/migrate/xxxxxxxxxxxxxx_enqueue_backfill_project_issues_count.rb
class EnqueueBackfillProjectIssuesCount < ActiveRecord::Migration[7.2]
  def up
    enqueue_background_data_migration("BackfillProjectIssuesCount")
  end

  def down
    remove_background_data_migration("BackfillProjectIssuesCount")
  end
end
```

`enqueue_background_data_migration` accepts additional configuration options which controls how the background migration is run. Check the [source code](https://github.com/fatkodima/online_migrations/blob/master/lib/online_migrations/background_migrations/migration_helpers.rb) for the list of all available configuration options.

## Custom Background Migration Arguments

Background migrations may need additional information, supplied via arguments, to run.

Declare that the migration class is accepting additional arguments:

```ruby
class MyMigrationWithArgs < OnlineMigrations::BackgroundMigration
  def initialize(arg1, arg2, ...)
    @arg1 = arg1
    @arg2 = arg2
    ...
  end
  # ...
end
```

And pass them when enqueuing:

```ruby
def up
  enqueue_background_data_migration("MyMigrationWithArgs", arg1, arg2, ...)
end
```

Make sure to also pass the arguments inside the `down` method of the migration:

```ruby
def down
  remove_background_data_migration("MyMigrationWithArgs", arg1, arg2, ...)
end
```

## Considerations when writing Background Migrations

* **Isolation**: Background migrations should be isolated and not use application code (for example, models defined in `app/models`). Since these migrations can take a long time to run it's possible for new versions to be deployed while they are still running.
* **Idempotence**: It should be safe to run `process_batch` multiple times for the same elements. It's important if the Background Migration errors and you run it again, because the same element that errored may be processed again. Make sure that in case that your migration job is going to be retried data integrity is guaranteed.

## Predefined background migrations

* `BackfillColumn` - backfills column(s) with scalar values (enqueue using `backfill_column_in_background`; or `backfill_column_for_type_change_in_background` if backfilling column for which type change is in progress)
* `CopyColumn` - copies data from one column(s) to other(s) (enqueue using `copy_column_in_background`)
* `DeleteAssociatedRecords` - deletes records associated with a parent object (enqueue using `delete_associated_records_in_background`)
* `DeleteOrphanedRecords` - deletes records with one or more missing relations (enqueue using `delete_orphaned_records_in_background`)
* `PerformActionOnRelation` - performs specific action on a relation or individual records (enqueue using `perform_action_on_relation_in_background`)
* `ResetCounters` - resets one or more counter caches to their correct value (enqueue using `reset_counters_in_background`)

**Note**: These migration helpers should be run inside the migration against the database where background migrations tables are defined.

## Depending on migrated data

You shouldn't depend on the data until the background data migration is finished. If having 100% of the data migrated is a requirement, then the `ensure_background_data_migration_succeeded` helper can be used to guarantee that the migration succeeded and the data fully migrated.

## Testing

At a minimum, it's recommended that the `#process_batch` method in your background migration is tested. You may also want to test the `#relation` and `#count` methods if they are sufficiently complex.

Example:

```ruby
# test/online_migrations/background_migrations/backfill_project_issues_count_test.rb

require "test_helper"

module OnlineMigrations
  module BackgroundMigrations
    class BackfillProjectIssuesCountTest < ActiveSupport::TestCase
      test "#process_batch performs an iteration" do
        rails = Project.create!(name: "Ruby on Rails")
        postgres = Project.create!(name: "PostgreSQL")

        2.times { rails.issues.create! }
        postgres.issues.create!

        migration = BackfillProjectIssuesCount.new
        migration.process_batch(migration.relation)

        assert_equal 2, rails.reload.issues_count
        assert_equal 1, postgres.reload.issues_count
      end
    end
  end
end
```

## Instrumentation

Background migrations use the [ActiveSupport::Notifications](http://api.rubyonrails.org/classes/ActiveSupport/Notifications.html) API.

You can subscribe to `background_migrations` events and log it, graph it, etc.

To get notified about specific type of events, subscribe to the event name followed by the `background_migrations` namespace. E.g. for retries use:

```ruby
# config/initializers/online_migrations.rb
ActiveSupport::Notifications.subscribe("retried.background_migrations") do |name, start, finish, id, payload|
  # background migration job object is available in payload[:background_migration_job]

  # Your code here
end
```

If you want to subscribe to every `background_migrations` event, use:

```ruby
# config/initializers/online_migrations.rb
ActiveSupport::Notifications.subscribe(/background_migrations/) do |name, start, finish, id, payload|
  # background migration job object is available in payload[:background_migration_job]

  # Your code here
end
```

Available events:

* `started.background_migrations`
* `process_batch.background_migrations`
* `completed.background_migrations`
* `retried.background_migrations`
* `throttled.background_migrations`

## Monitoring Background Migrations

Background Migrations can be in various states during its execution:

* **enqueued**: A migration has been enqueued by the user.
* **running**: A migration is being performed by a migration executor.
* **paused**: A migration was paused in the middle of the run by the user.

  To manually pause a migration, you can run:

  ```ruby
  migration = OnlineMigrations::BackgroundMigrations::Migration.find(id)
  migration.paused!
  ```
* **finishing**: A migration is being manually finishing inline by the user.
  For example, if you need to manually perform a background migration until it is finished, you can run:

  ```ruby
  migration = OnlineMigrations::BackgroundMigrations::Migration.find(id)
  runner = OnlineMigrations::BackgroundMigrations::MigrationRunner.new(migration)
  runner.finish
  ```
  Note: In normal circumstances, this should not be used since background migrations should be run and finished by the scheduler.
* **failed**: A migration raises an exception when running.
* **succeeded**: A migration finished without error.
* **cancelled**: A migration was cancelled by the user.

To get the progress (assuming `#count` method on background migration class was defined):

```ruby
migration = OnlineMigrations::BackgroundMigrations::Migration.find(id)
migration.progress # value from 0 to 100.0
```

**Note**: It will be easier to work with background migrations through some kind of Web UI, but until it is implemented, we can work with them only manually.

## Retrying a failed migration

To retry a failed migration, run:

```ruby
migration = OnlineMigrations::BackgroundMigrations::Migration.find(id)
migration.retry # => `true` if scheduled to be retried, `false` - if not
```

The migration will be retried on the next Scheduler run.

## Cancelling a migration

To cancel an existing migration from future performing, run:

```ruby
migration = OnlineMigrations::BackgroundMigrations::Migration.find(id)
migration.cancel
```

## Configuring

There are a few configurable options for the Background Migrations. Custom configurations should be placed in a `online_migrations.rb` initializer.

Check the [source code](https://github.com/fatkodima/online_migrations/blob/master/lib/online_migrations/background_migrations/config.rb) for the list of all available configuration options.

**Note**: You can dynamically change certain migration parameters while the migration is run.
For example,
```ruby
migration = OnlineMigrations::BackgroundMigrations::Migration.find(id)
migration.update!(
  batch_size: 50_000,      # The # of records migration will update per run
  sub_batch_size: 10_000,  # The # of records migration will update via single `UPDATE`
  batch_pause: 1.second,   # Minimum time (in seconds) between successive migration runs
  sub_batch_pause_ms: 20   # Minimum time (in ms) between successive migration `UPDATE`s
)
```

### Customizing the error handler

Exceptions raised while a Background Migration is performing are rescued and information about the error is persisted in the database.

If you want to integrate with an exception monitoring service (e.g. Bugsnag), you can define an error handler:

```ruby
# config/initializers/online_migrations.rb

config.background_migrations.error_handler = ->(error, errored_job) do
  Bugsnag.notify(error) do |notification|
    notification.add_metadata(:background_migration, { name: errored_job.migration_name })
  end
end
```

The error handler should be a lambda that accepts 2 arguments:

* `error`: The exception that was raised.
* `errored_job`: An `OnlineMigrations::BackgroundMigrations::MigrationJob` object that represents a failed batch.

### Customizing the background migrations path

`OnlineMigrations.config.background_migrations.migrations_path` can be configured to define where generated background migrations will be placed.

```ruby
# config/initializers/online_migrations.rb

config.background_migrations.migrations_path = "app/lib"
```

If no value is specified, it will default to `"lib"`.

### Customizing the background migrations module

`config.background_migrations.migrations_module` can be configured to define the module in which
background migrations will be placed.

```ruby
# config/initializers/online_migrations.rb

config.background_migrations.migrations_module = "BackgroundMigrationsModule"
```

If no value is specified, it will default to `"OnlineMigrations::BackgroundMigrations"`.

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
