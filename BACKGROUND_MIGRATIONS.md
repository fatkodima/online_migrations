# Background Migrations

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
  runner "OnlineMigrations::BackgroundMigrations::Scheduler.run"
end
```

## Creating a Background Migration

A generator is provided to create background migrations. Generate a new background migration by running:

```bash
$ bin/rails generate online_migrations:background_migration backfill_project_issues_count
```

This creates the background migration file `lib/online_migrations/background_migrations/backfill_project_issues_count.rb`.

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
# db/migrate/xxxxxxxxxxxxxx_backfill_project_issues_count.rb
# ...
def up
  enqueue_background_migration("BackfillProjectIssuesCount")
end
# ...
```

`enqueue_background_migration` accepts additional configuration options which controls how the background migration is run. Check the [source code](https://github.com/fatkodima/online_migrations/blob/master/lib/online_migrations/background_migrations/online_migrations.rb) for the list of all available configuration options.

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
enqueue_background_migration("MyMigrationWithArgs", arg1, arg2, ...)
```

## Considerations when writing Background Migrations

* **Isolation**: Background migrations should be isolated and not use application code (for example, models defined in `app/models`). Since these migrations can take a long time to run it's possible for new versions to be deployed while they are still running.
* **Idempotence**: It should be safe to run `process_batch` multiple times for the same elements. It's important if the Background Migration errors and you run it again, because the same element that errored may be processed again. Make sure that in case that your migration job is going to be retried data integrity is guaranteed.

## Predefined background migrations

* `BackfillColumn` - backfills column(s) with scalar values (enqueue using `backfill_column_in_background`)
* `CopyColumn` - copies data from one column(s) to other(s) (enqueue using `copy_column_in_background`)
* `DeleteAssociatedRecords` - deletes records associated with a parent object (enqueue using `delete_associated_records_in_background`)
* `DeleteOrphanedRecords` - deletes records with one or more missing relations (enqueue using `delete_orphaned_records_in_background`)
* `PerformActionOnRelation` - performs specific action on a relation or indvidual records (enqueue using `perform_action_on_relation_in_background`)
* `ResetCounters` - resets one or more counter caches to their correct value (enqueue using `reset_counters_in_background`)

## Testing

At a minimum, it's recommended that the `#process_batch` method in your background migration is tested. You may also want to test the `#relation` and `#count` methods if they are sufficiently complex.

Example:

```ruby
# test/online_migrations/background_migrations/backfill_project_issues_count_test.rb

require "test_helper"

module OnlineMigrations
  module BackgroundMigrations
    class BackfillProjectIssuesCountTest < ActiveSupport::TestCase
      test "#process_batch performs a background migration iteration" do
        rails = Project.create!(name: "rails")
        postgres = Project.create!(name: "PostgreSQL")

        2.times { rails.issues.create! }
        _postgres_issue = postgres.issues.create!

        BackfillProjectIssuesCount.new.process_batch(Project.all)

        assert_equal 2, rails.issues_count
        assert_equal 1, postgres.issues_count
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

To get the progress (assuming `#count` method on background migration class was defined):

```ruby
migration = OnlineMigrations::BackgroundMigrations::Migration.find(id)
migration.progress # value from 0 to 1.0
```

**Note**: It will be easier to work with background migrations through some kind of Web UI, but until it is implemented, we can work with them only manually.

## Configuring

There are a few configurable options for the Background Migrations. Custom configurations should be placed in a `online_migrations.rb` initializer.

**Note**: Check the [source code](https://github.com/fatkodima/online_migrations/blob/master/lib/online_migrations/background_migrations/config.rb) for the list of all available configuration options.

### Throttling

Background Migrations often modify a lot of data and can be taxing on your database. There is a throttling mechanism that can be used to throttle a background migration when a given condition is met. If a migration is throttled, it will be interrupted and retried on the next Scheduler cycle run.

Specify the throttle condition as a block:

```ruby
# config/initializers/online_migrations.rb

OnlineMigrations.config.backround_migrations.throttler = -> { DatabaseStatus.unhealthy? }
```

Note that it's up to you to define a throttling condition that makes sense for your app. For example, you can check various PostgreSQL metrics such as replication lag, DB threads, whether DB writes are available, etc.

### Customizing the error handler

Exceptions raised while a Background Migration is performing are rescued and information about the error is persisted in the database.

If you want to integrate with an exception monitoring service (e.g. Bugsnag), you can define an error handler:

```ruby
# config/initializers/online_migrations.rb

OnlineMigrations.config.backround_migrations.error_handler = ->(error, errored_job) do
  Bugsnag.notify(error) do |notification|
    notification.add_metadata(:background_migration, { name: errored_job.migration_name })
  end
end
```

The error handler should be a lambda that accepts 2 arguments:

* `error`: The exception that was raised.
* `errored_job`: An `OnlineMigrations::BackgroundMigrations::MigrationJob` object that represents a failed batch.
* `errored_element`: The `OnlineMigrations::BackgroundMigrations::MigrationJob` object representing a batch,
  that was being processed when the Background Migration raised an exception.

### Customizing the background migrations module

`OnlineMigrations.config.background_migrations.migrations_module` can be configured to define the module in which
background migrations will be placed.

```ruby
# config/initializers/online_migrations.rb

OnlineMigrations.config.background_migrations.migrations_module = "BackgroundMigrationsModule"
```

If no value is specified, it will default to `OnlineMigrations::BackgroundMigrations`.

### Customizing the backtrace cleaner

`OnlineMigrations.config.background_migrations.backtrace_cleaner` can be configured to specify a backtrace cleaner to use when a Background Migration errors and the backtrace is cleaned and persisted. An `ActiveSupport::BacktraceCleaner` should be used.

```ruby
# config/initializers/online_migrations.rb

cleaner = ActiveSupport::BacktraceCleaner.new
cleaner.add_silencer { |line| line =~ /ignore_this_dir/ }

OnlineMigrations.config.background_migrations.backtrace_cleaner = cleaner
```

If none is specified, the default `Rails.backtrace_cleaner` will be used to clean backtraces.
