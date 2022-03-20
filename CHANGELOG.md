## master (unreleased)

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
