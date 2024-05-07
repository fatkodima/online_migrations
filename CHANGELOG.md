## master (unreleased)

- Fix setting `started_at`/`finished_at` for parents of sharded background schema migrations
- Improve retrying of failed sharded background migrations
- Fix a bug when retried background data migration can not start
- Do not run multiple background schema migrations on the same table at the same time

## 0.17.1 (2024-04-28)

- Fix raising in development when using sharding and background index creation/removal was not enqueued

## 0.17.0 (2024-04-23)

- Fix background migrations `#progress` possibility to fail with zero division error
- Add `ensure_background_data_migration_succeeded` and `ensure_background_schema_migration_succeeded` migration helpers
- Raise in development when background index creation/removal was not enqueued
- Suggest two migrations for adding foreign keys
- Reraise errors when running background schema migrations inline

## 0.16.1 (2024-03-29)

- Improve error message when background schema migration name is already taken
- Fix copying column background migration to work with primary keys added via `initialize_column_type_change`

## 0.16.0 (2024-03-28)

- Add support for asynchronous creation/removal of indexes

    See `docs/background_schema_migrations.md` for the feature description.

## 0.15.0 (2024-03-19)

- Reraise errors when running background migrations inline
- Add `remove_background_migration` migration helper
- Allow adding bigint foreign keys referencing integer primary keys
- Fix `add_reference_concurrently` to check for mismatched key types

## 0.14.1 (2024-02-21)

- Fix `MigrationRunner` to consider `run_background_migrations_inline` proc

## 0.14.0 (2024-02-01)

- Add ability to configure whether background migrations should be run inline

    The previous behavior of running inline in development and test environments is preserved, unless overriden.

    ```ruby
    config.run_background_migrations_inline = -> { Rails.env.local? }
    ```

## 0.13.1 (2024-01-23)

- Fix calculation of batch ranges for background migration created with explicit ranges

## 0.13.0 (2024-01-22)

- Add ability to configure the path where generated background migrations will be placed

    ```ruby
    # It is placed in lib/ by default.
    config.background_migrations.migrations_path = "app/lib"
    ```

- Reduce number of queries needed to calculate batch ranges for background migrations
- Fix `finalize_column_type_change` to not recreate already existing indexes on the temporary column
- Remove potentially heavy queries used to get the ranges of a background migration

## 0.12.0 (2024-01-18)

- Require passing model name for background migration helpers when using multiple databases
- Add `statement_timeout` configuration option

- Make `lock_timeout` argument optional for `config.lock_retrier`

    This way, a default lock timeout value will be used (configured in `database.yml` or for the database user).

- Fix a bug that can lead to unfinished children of a sharded background migration

## 0.11.1 (2024-01-11)

- Fix calculation of batch ranges for sharded background migrations

## 0.11.0 (2024-01-09)

- Support sharding for background migrations

    Now, if a `relation` inside background migration definition is defined on a sharded model,
    then that background migration would automatically run on all the shards.

    To get all the new sharding related schema changes, you need to run:

    ```sh
    $ bin/rails generate online_migrations:upgrade
    $ bin/rails db:migrate
    ```

- Change background migration `progress` to return values in range from 0.0 to 100.0

    Previously, these were values in range from 0.0 to 1.0 and caused confusion

- Copy exclusion constraints when changing column type
- Update `revert_finalize_columns_type_change` to not remove indexes, foreign keys etc
- Fix verbose query logging when `ActiveRecord::Base.logger` is `nil`
- Add a shortcut for running background migrations

    ```ruby
    # Before:
    OnlineMigrations::BackgroundMigrations::Scheduler.run
    # After
    OnlineMigrations.run_background_migrations
    ```

- Add support for `:type_cast_function` to `initialize_column_type_change` helper
- Drop support for Ruby < 2.7 and Rails < 6.1

## 0.10.0 (2023-12-12)

- Add `auto_analyze` configuration option
- Add `alphabetize_schema` configuration option
- Fix `backfill_column_for_type_change_in_background` for cast expressions
- Fix copying indexes with long names when changing column type
- Enhance error messages with the link to the detailed description

## 0.9.2 (2023-11-02)

- Fix checking which expression indexes to copy when changing column type

## 0.9.1 (2023-10-30)

- Fix copying expression indexes when changing column type

## 0.9.0 (2023-10-27)

- Add ability to use custom raw sql for `backfill_column_for_type_change`'s `type_cast_function`

    ```ruby
    backfill_column_for_type_change(:users, :company_id, type_cast_function: Arel.sql("company_id::integer"))
    ```

- Fix version safety with `revert`

## 0.8.2 (2023-09-26)

- Promote check constraint to `NOT NULL` on PostgreSQL >= 12 when changing column type
- Fix `safety_assured` with `revert`

## 0.8.1 (2023-08-04)

- Fix `update_columns_in_batches` when multiple columns are passed
- Fix reverting adding/removing not null and text limit constraints

## 0.8.0 (2023-07-24)

- Add check for `change_column_default`
- Add check for `add_unique_constraint` (Active Record >= 7.1)
- Add check for `add_column` with stored generated columns

## 0.7.3 (2023-05-30)

- Fix removing columns having expression indexes on them

## 0.7.2 (2023-03-08)

- Suggest additional steps for safely renaming a column if Active Record `enumerate_columns_in_select_statements`
  setting is enabled (implemented in Active Record 7+, disabled by default)
- Fix `add_reference_concurrently` to correctly check for existence of foreign keys
- Fix column quoting in `add_not_null_constraint`

## 0.7.1 (2023-02-22)

- Fix Schema Cache to correctly retrieve metadata from renamed tables

## 0.7.0 (2023-02-14)

- Add support for renaming multiple columns at once in the same table
- Fix quoting table/column names across the library
- Fix deffered foreign keys support in `add_foreign_key` (Active Record >= 7)
- Reset attempts of failing jobs before executing background migration inline

## 0.6.0 (2023-02-04)

- Ignore internal Active Record migrations compatibility related options when suggesting a safe column type change
- Added check for `add_exclusion_constraint`
- Fix preserving old column options (`:comment` and `:collation`) when changing column type
- Set `NOT NULL` during new column creation when changing column type for PostgreSQL >= 11

## 0.5.4 (2023-01-03)

- Support ruby 3.2.0

## 0.5.3 (2022-11-10)

- Fix removing index by name
- Fix multiple databases support for `start_after` and `target_version` configs
- Fix error when `Rails` defined without `Rails.env`
- Improve error message for adding column with a NULL default for PostgreSQL < 11

## 0.5.2 (2022-10-04)

- Fix sequence resetting in tests that use fixtures

- Fix `update_column_in_batches` for SQL subquery values

    It generated inefficient queries before, e.g.:

    ```ruby
    update_column_in_batches(:users, :comments_count, Arel.sql(<<~SQL))
      (select count(*) from comments where comments.user_id = users.id)
    SQL
    ```

    Generated SQL queries before:
    ```sql
    update users
    set comments_count = (..count subquery..)
    where comments_count is null or comments_count != (..count subquery..)
    ```

    Generated SQL queries now:
    ```sql
    update users set comments_count = (..count subquery..)
    ```

- Fix check for `add_column` with `default: nil` for PostgreSQL < 11
- Replacing a unique index when other unique index with the prefix of columns exists is safe

## 0.5.1 (2022-07-19)

- Raise for possible index corruption in all environments (previously, the check was made only
  in the production environment)

## 0.5.0 (2022-06-23)

- Added check for index corruption with PostgreSQL 14.0 to 14.3

- No need to separately remove indexes when removing a column from the small table

- Add ability to perform specific action on a relation or individual records using background migrations

    Example, assuming you have lots and lots of fraud likes:

    ```ruby
    class DeleteFraudLikes < ActiveRecord::Migration[7.0]
      def up
        perform_action_on_relation_in_background("Like", { fraud: true }, :delete_all)
      end
    end
    ```

    Example, assuming you added a new column to the users and want to populate it:

    ```ruby
    class User < ApplicationRecord
      def generate_invite_token
        self.invite_token = # some complex logic
      end
    end

    perform_action_on_relation_in_background("User", { invite_token: nil }, :generate_invite_token)
    ```

    You can use `delete_all`/`destroy_all`/`update_all` for the whole relation or run specific methods on individual records.

- Add ability to delete records associated with a parent object using background migrations

    ```ruby
      class Link < ActiveRecord::Base
        has_many :clicks
      end

      class Click < ActiveRecord::Base
        belongs_to :link
      end

      class DeleteSomeLinkClicks < ActiveRecord::Migration[7.0]
        def up
          some_link = ...
          delete_associated_records_in_background("Link", some_link.id, :clicks)
        end
      end
    ```

- Add ability to delete orphaned records using background migrations

    ```ruby
      class User < ApplicationRecord
        has_many :posts
      end

      class Post < ApplicationRecord
        belongs_to :author, class_name: 'User'
      end

      class DeleteOrphanedPosts < ActiveRecord::Migration[7.0]
        def up
          delete_orphaned_records_in_background("Post", :author)
        end
      end
    ```

## 0.4.1 (2022-03-21)

- Fix missing options in suggested command for columns removal
- Fix retrieving raw postgresql connection

## 0.4.0 (2022-03-17)

- Lazy load this gem

- Add ability to reset counter caches using background migrations

    ```ruby
      class User < ApplicationRecord
        has_many :projects
      end

      class Project < ApplicationRecord
        belongs_to :user, counter_cache: true
      end

      class ResetUsersProjectsCount < ActiveRecord::Migration[7.0]
        def up
          reset_counters_in_background("User", :projects)
        end
      end
    ```

- Accept `0` as `batch_pause` value for background migrations
- Ignore default scopes in `CopyColumn` and `BackfillColumn` background migrations
- Raise an error for unsupported database versions
- Fix backfilling code in suggestion for changing column's NOT NULL

New safe operations

- Changing between `text` and `citext` when not indexed
- Changing a `string` column to a `citext` column when not indexed
- Changing a `citext` column to a `string` column with no length limit
- Increasing the `:precision` of an `interval` column
- Changing a `cidr` column to an `inet` column
- Changing an `xml` column to a `text` column
- Changing an `xml` column to a `string` column with no `:limit`
- Changing a `bit` column to a `bit_varying` column
- Increasing or removing the `:limit` of a `bit_varying` column

New unsafe operations

- Decreasing `:precision` of a `datetime` column
- Decreasing `:limit` of a `timestamptz` column
- Decreasing `:limit` of a `bit_varying` column
- Adding a `:limit` to a `bit_varying` column

## 0.3.0 (2022-02-10)

- Support ActiveRecord 7.0+ versioned schemas

- Check for addition of single table inheritance column

    See [Adding a single table inheritance column](https://github.com/fatkodima/online_migrations#adding-a-single-table-inheritance-column) for details

- Add a way to log every SQL query to stdout

    See [Verbose SQL logs](https://github.com/fatkodima/online_migrations#verbose-sql-logs) for details

- Ignore new tables when checking for removing table with multiple fkeys
- Fix backfilling column in add_column_with_default when default is an expression

## 0.2.0 (2022-01-31)

- Check removing a table with multiple foreign keys

- Check for mismatched reference column types

    For example, it detects cases like:

    ```ruby
    class AddUserIdToProjects < ActiveRecord::Migration[7.0]
      def change
        add_column :projects, :user_id, :integer
      end
    end
    ```

    where `users.id` is of type `bigint`.

- Add support for multiple databases to `start_after` and `target_version` configuration options

    ```ruby
    OnlineMigrations.configure do |config|
      config.start_after = { primary: 20211112000000, animals: 20220101000000 }
      config.target_version = { primary: 10, animals: 14.1 }
    end
    ```

- Do not suggest `ignored_columns` when removing columns for Active Record 4.2 (`ignored_columns` was introduced in 5.0)

- Check replacing indexes

    For example, you have an index on `projects.creator_id`. But decide, it is better to have a multicolumn index on `[creator_id, created_at]`:

    ```ruby
    class AddIndexOnCreationToProjects < ActiveRecord::Migration[7.0]
      disable_ddl_transaction!

      def change
        remove_index :projects, :creator_id, algorithm: :concurrently # (1)
        add_index :projects, [:creator_id, :created_at], algorithm: :concurrently # (2)
      end
    end
    ```

    If there is no existing indexes covering `creator_id`, removing an old index (1) before replacing it with the new one (2) might result in slow queries while building the new index.
    A safer approach is to swap removing the old and creation of the new index operations.

## 0.1.0 (2022-01-17)

- First release
