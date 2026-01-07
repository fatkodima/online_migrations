# Background Data Migrations

When a project grows, your database starts to be heavy and changing the data through the deployment process can be very painful.

Background data migrations should be used to perform data migrations on large tables or when the migration will take a lot of time. For example, you can use background data migrations to migrate data that’s stored in a single JSON column to a separate table instead or backfill some column's value from an API.

**Note**: You probably don't need to use background migrations for smaller projects, since updating data directly on smaller databases will be perfectly fine and will not block the deployment too much.

## Requirements

Data migrations uses [sidekiq iterable job](https://github.com/sidekiq/sidekiq/wiki/Iteration) under the hood and so requires `sidekiq` 7.3.3+ to work.

## Installation

Make sure you have migration files generated when installed this gem:

```sh
$ bin/rails generate online_migrations:install
```

Start a background data migrations scheduler. For example, to run it on cron using [whenever gem](https://github.com/javan/whenever) add the following lines to its `schedule.rb` file:

```ruby
every 1.minute do
  runner "OnlineMigrations.run_background_data_migrations"
end
```

## Creating a Data Migration

A generator is provided to create data migrations. Generate a new data migration by running:

```bash
$ bin/rails generate online_migrations:data_migration backfill_project_issues_count
```

This creates a data migration file `lib/online_migrations/data_migrations/backfill_project_issues_count.rb`
and a regular migration file `db/migrate/xxxxxxxxxxxxxx_enqueue_backfill_project_issues_count.rb` where it is enqueued.

The generated class is a subclass of `OnlineMigrations::DataMigration` that implements:

* `collection`: return a collection to be processed. Can be any of `ActiveRecord::Relation`, `ActiveRecord::Batches::BatchEnumerator`, `Array`, or `Enumerator`
* `process`: the action to be performed on each item from the `collection`
* `count`: return total count of iterations to be performed (optional, to be able to show progress)

Example:

```ruby
# lib/online_migrations/data_migrations/backfill_project_issues_count.rb

module OnlineMigrations
  module DataMigrations
    class BackfillProjectIssuesCount < OnlineMigrations::DataMigration
      class Project < ActiveRecord::Base; end

      def collection
        Project.in_batches(of: 100)
      end

      def process(relation)
        relation.update_all(<<~SQL)
          issues_count = (
            SELECT COUNT(*)
            FROM issues
            WHERE issues.project_id = projects.id
          )
        SQL
      end

      def count
        collection.count
      end
    end
  end
end
```

### Data Migrations with Custom Enumerators

If you have a special use case requiring iteration over an unsupported collection type,
such as external resources fetched from some API, you can implement the `build_enumerator(cursor:)`
method in your data migration.

This method should return an `Enumerator`, yielding pairs of `[item, cursor]`. Online Migrations
takes care of persisting the current cursor position and will provide it as the `cursor` argument
if your data migration is interrupted or resumed. The `cursor` is stored as a `String`,
so your custom enumerator should handle serializing/deserializing the value if required.

```ruby
# lib/online_migrations/data_migrations/custom_enumerator_migration.rb

module OnlineMigrations
  module DataMigrations
    class CustomEnumeratorMigration < OnlineMigrations::DataMigration
      def build_enumerator(cursor:)
        after_id = cursor&.to_i
        PostAPI.index(after_id: after_id).map { |post| [post, post.id] }.to_enum
      end

      def process(post)
        Post.create!(post)
      end
    end
  end
end
```

### Customizing the Batch Size

When processing records from an `ActiveRecord::Relation`, records are fetched in batches internally, and then each record is passed to the `#process` method.
The gem will query the database to fetch records in batches of 100 by default, but the batch size can be modified using the `collection_batch_size` macro:

```ruby
module OnlineMigrations
  module DataMigrations
    class UpdatePostsMigration < OnlineMigrations::DataMigration
    # Fetch records in batches of 1000
    collection_batch_size(1000)

    def collection
      Post.all
    end

    def process(post)
      post.update!(content: "New content!")
    end
  end
end
```

## Enqueueing a Data Migration

You can enqueue a data migration to be run by the scheduler via:

```ruby
# db/migrate/xxxxxxxxxxxxxx_enqueue_backfill_project_issues_count.rb
class EnqueueBackfillProjectIssuesCount < ActiveRecord::Migration[8.0]
  def up
    enqueue_background_data_migration("BackfillProjectIssuesCount")
  end

  def down
    remove_background_data_migration("BackfillProjectIssuesCount")
  end
end
```

`enqueue_background_data_migration` accepts additional configuration options which controls how the data migration is run. Check the [source code](https://github.com/fatkodima/online_migrations/blob/master/lib/online_migrations/background_data_migrations/migration_helpers.rb) for the list of all available configuration options.

## Custom Data Migration Arguments

Data migrations may need additional information to run, which can be provided via arguments.

Declare that the migration class is accepting additional arguments:

```ruby
class MyMigrationWithArgs < OnlineMigrations::DataMigration
  def initialize(arg1, arg2, ...)
    @arg1 = arg1
    @arg2 = arg2
    # ...
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

## Considerations when writing Data Migrations

* **Isolation**: Data migrations should be isolated and not use application code (for example, models defined in `app/models`). Since these migrations can take a long time to run it's possible for new versions to be deployed while they are still running.
* **Idempotence**: It should be safe to run `process` multiple times for the same elements. It's important, because if the data migration errored and you run it again, the same element that errored may be processed again. Make sure that if your migration is going to be retried the data integrity is guaranteed.

## Predefined data migrations

* `BackfillColumn` - backfills column(s) with scalar values (enqueue using `backfill_column_in_background`; or `backfill_column_for_type_change_in_background` if backfilling column for which type change is in progress)
* `CopyColumn` - copies data from one column(s) to other(s) (enqueue using `copy_column_in_background`)
* `DeleteAssociatedRecords` - deletes records associated with a parent object (enqueue using `delete_associated_records_in_background`)
* `DeleteOrphanedRecords` - deletes records with one or more missing relations (enqueue using `delete_orphaned_records_in_background`)
* `PerformActionOnRelation` - performs specific action on a relation or individual records (enqueue using `perform_action_on_relation_in_background`)
* `ResetCounters` - resets one or more counter caches to their correct value (enqueue using `reset_counters_in_background`)

**Note**: These migration helpers should be run inside the migration files against the database where background migrations tables are defined.

## Depending on migrated data

You shouldn't depend on the data until the background data migration is finished. If having 100% of the data migrated is a requirement, then the `ensure_background_data_migration_succeeded` helper can be used to guarantee that the migration succeeded and the data fully migrated.

## Testing

At a minimum, it's recommended that the `#process` method in your data migration is tested. You may also want to test the `#collection` and `#count` methods if they are sufficiently complex.

Example:

```ruby
# test/online_migrations/data_migrations/backfill_project_issues_count_test.rb

require "test_helper"

module OnlineMigrations
  module DataMigrations
    class BackfillProjectIssuesCountTest < ActiveSupport::TestCase
      test "#process backfills issues_count" do
        rails = Project.create!(name: "Ruby on Rails")
        postgres = Project.create!(name: "PostgreSQL")

        2.times { rails.issues.create! }
        postgres.issues.create!

        migration = BackfillProjectIssuesCount.new
        migration.collection.each do |relation|
          migration.process(relation)
        end

        assert_equal 2, rails.reload.issues_count
        assert_equal 1, postgres.reload.issues_count
      end
    end
  end
end
```

## Instrumentation

Data migrations use the [ActiveSupport::Notifications](http://api.rubyonrails.org/classes/ActiveSupport/Notifications.html) API.

You can subscribe to `background_data_migrations` events and log it, graph it, etc.

To get notified about specific type of events, subscribe to the event name followed by the `background_data_migrations` namespace.

```ruby
# config/initializers/online_migrations.rb
ActiveSupport::Notifications.subscribe("started.background_data_migrations") do |name, start, finish, id, payload|
  # background data migration object is available in payload[:migration]

  # Your code here
end
```

If you want to subscribe to every `background_data_migrations` event, use:

```ruby
# config/initializers/online_migrations.rb
ActiveSupport::Notifications.subscribe(/background_data_migrations/) do |name, start, finish, id, payload|
  # background data migration object is available in payload[:migration]

  # Your code here
end
```

Available events:

* `started.background_data_migrations`
* `completed.background_data_migrations`
* `throttled.background_data_migrations`

### Using Data Migration Callbacks

The data migrations provides callbacks that hook into its life cycle.

Available callbacks are:

* `after_start`
* `around_process`
* `after_resume`
* `after_stop`
* `after_complete`
* `after_pause`
* `after_cancel`

```ruby
module OnlineMigrations
  module DataMigrations
    class BackfillProjectIssuesCount < OnlineMigrations::DataMigration
      def after_start
        NotifyJob.perform_later(self.class.name)
      end

      # ...
    end
  end
end
```

## Monitoring Data Migrations

Data Migrations can be in various states during its execution:

* **enqueued**: A migration has been enqueued by the user.
* **running**: A migration is being performed by a migration executor.
* **pausing**: A migration has been told to pause but is finishing work.
* **paused**: A migration was paused in the middle of the run by the user.

  To manually pause a migration, you can run:

  ```ruby
  migration = OnlineMigrations::DataMigrations::Migration.find(id)
  migration.pause
  ```

* **failed**: A migration raises an exception when running.
* **succeeded**: A migration finished without error.
* **cancelling**: A migration has been told to cancel but is finishing work.
* **cancelled**: A migration was cancelled by the user.

  To manually cancel a migration, you can run:

  ```ruby
  migration = OnlineMigrations::DataMigrations::Migration.find(id)
  migration.cancel
  ```

* **delayed**: A migration was created, but waiting approval from the user to start running.

  To create a delayed migration, you can pass a `delayed: true` option:

  ```ruby
  enqueue_background_data_migration("MyMigration", delay: true)
  ```

To get the progress (assuming `#count` method on data migration class was defined):

```ruby
migration = OnlineMigrations::DataMigrations::Migration.find(id)
migration.progress # value from 0 to 100.0
```

**Note**: It will be easier to work with background migrations through some kind of Web UI, but until it is implemented, we can work with them only manually.

## Retrying a failed migration

To retry a failed migration, run:

```ruby
migration = OnlineMigrations::DataMigrations::Migration.find(id)
migration.retry # => `true` if scheduled to be retried, `false` - if not
```

The migration will be retried on the next Scheduler run.

## Configuring

There are a few configurable options for the data migrations. Custom configurations should be placed in a `online_migrations.rb` initializer.

Check the [source code](https://github.com/fatkodima/online_migrations/blob/master/lib/online_migrations/background_data_migrations/config.rb) for the list of all available configuration options.

### Customizing the error handler

Exceptions raised while a data migration is performing are rescued and information about the error is persisted in the database.

If you want to integrate with an exception monitoring service (e.g. Bugsnag), you can define an error handler:

```ruby
# config/initializers/online_migrations.rb

config.background_data_migrations.error_handler = ->(error, errored_migration) do
  Bugsnag.notify(error) do |notification|
    notification.add_metadata(:background_data_migration, { name: errored_migration.name })
  end
end
```

The error handler should be a lambda that accepts 2 arguments:

* `error`: The exception that was raised.
* `errored_migration`: An `OnlineMigrations::BackgroundDataMigrations::Migration` object that represents a migration.

### Customizing the data migrations path

`OnlineMigrations.config.background_data_migrations.migrations_path` can be configured to define where generated data migrations will be placed.

```ruby
# config/initializers/online_migrations.rb

config.background_data_migrations.migrations_path = "app/lib"
```

If no value is specified, it will default to `"lib"`.

### Customizing the data migrations module

`config.background_data_migrations.migrations_module` can be configured to define the module in which
data migrations will be placed.

```ruby
# config/initializers/online_migrations.rb

config.background_data_migrations.migrations_module = "DataMigrationsModule"
```

If no value is specified, it will default to `"OnlineMigrations::DataMigrations"`.

### Customizing the underlying sidekiq job class

A custom sidekiq job class can be configured to define a job class for your data migrations to use.

```ruby
# config/initializers/online_migrations.rb

config.background_data_migrations.job = "CustomMigrationJob"
```

```ruby
# app/jobs/custom_migration_job.rb

class CustomMigrationJob < OnlineMigrations::DataMigrations::MigrationJob
  sidekiq_options queue: "low"
end
```

The job class **must inherit** from `OnlineMigrations::DataMigrations::MigrationJob`.

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

#### Parallelize processing by shards

By default, only a single data migration at a time is processed. To process a single data migration at a time *per shard*:

```ruby
[:shard_one, :shard_two, :shard_three].each do |shard|
  every 1.minute do
    runner "OnlineMigrations.run_background_data_migrations(shard: :#{shard})"
  end
end
```

#### Change processing concurrency

By default, only a *single* data migration at a time is processed. To change the concurrency:

```ruby
every 1.minute do
  # Run 2 data migrations in parallel.
  runner "OnlineMigrations.run_background_data_migrations(concurrency: 2)"
end
```

**Note**: This configuration works perfectly well in combination with the `:shard` configuration from the previous section.
