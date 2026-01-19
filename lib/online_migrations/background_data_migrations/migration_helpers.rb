# frozen_string_literal: true

module OnlineMigrations
  module BackgroundDataMigrations
    module MigrationHelpers
      # Backfills column data using background migrations.
      #
      # @param table_name [String, Symbol]
      # @param column_name [String, Symbol]
      # @param value
      # @param model_name [String] If Active Record multiple databases feature is used,
      #     the class name of the model to get connection from.
      # @param options [Hash] used to control the behavior of background migration.
      #     See `#enqueue_background_data_migration`
      #
      # @return [OnlineMigrations::BackgroundDataMigrations::Migration]
      #
      # @example
      #   backfill_column_in_background(:users, :admin, false)
      #
      # @example Additional background migration options
      #   backfill_column_in_background(:users, :admin, false, batch_size: 10_000)
      #
      # @note This method is better suited for large tables (10/100s of millions of records).
      #     For smaller tables it is probably better and easier to use more flexible `update_column_in_batches`.
      #
      # @note Consider `backfill_columns_in_background` when backfilling multiple columns
      #   to avoid rewriting the table multiple times.
      #
      def backfill_column_in_background(table_name, column_name, value, model_name: nil, **options)
        backfill_columns_in_background(table_name, { column_name => value },
                                       model_name: model_name, **options)
      end

      # Same as `backfill_column_in_background` but for multiple columns.
      #
      # @param updates [Hash] keys - column names, values - corresponding values
      #
      # @example
      #   backfill_columns_in_background(:users, { admin: false, status: "active" })
      #
      # @see #backfill_column_in_background
      #
      def backfill_columns_in_background(table_name, updates, model_name: nil, **options)
        if model_name.nil? && Utils.multiple_databases?
          raise ArgumentError, "You must pass a :model_name when using multiple databases."
        end

        model_name = model_name.name if model_name.is_a?(Class)

        enqueue_background_data_migration(
          "BackfillColumn",
          table_name,
          updates,
          model_name,
          **options
        )
      end

      # Backfills data from the old column to the new column using background migrations.
      #
      # @param table_name [String, Symbol]
      # @param column_name [String, Symbol]
      # @param model_name [String] If Active Record multiple databases feature is used,
      #     the class name of the model to get connection from.
      # @param type_cast_function [String, Symbol] Some type changes require casting data to a new type.
      #     For example when changing from `text` to `jsonb`. In this case, use the `type_cast_function` option.
      #     You need to make sure there is no bad data and the cast will always succeed
      # @param options [Hash] used to control the behavior of background migration.
      #     See `#enqueue_background_data_migration`
      #
      # @return [OnlineMigrations::BackgroundDataMigrations::Migration]
      #
      # @example
      #   backfill_column_for_type_change_in_background(:files, :size)
      #
      # @example With type casting
      #   backfill_column_for_type_change_in_background(:users, :settings, type_cast_function: "jsonb")
      #
      # @example Additional background migration options
      #   backfill_column_for_type_change_in_background(:files, :size, batch_size: 10_000)
      #
      # @note This method is better suited for large tables (10/100s of millions of records).
      #     For smaller tables it is probably better and easier to use more flexible `backfill_column_for_type_change`.
      #
      def backfill_column_for_type_change_in_background(table_name, column_name, model_name: nil,
                                                        type_cast_function: nil, **options)
        backfill_columns_for_type_change_in_background(
          table_name,
          column_name,
          model_name: model_name,
          type_cast_functions: { column_name => type_cast_function },
          **options
        )
      end

      # Same as `backfill_column_for_type_change_in_background` but for multiple columns.
      #
      # @param type_cast_functions [Hash] if not empty, keys - column names,
      #   values - corresponding type cast functions
      #
      # @see #backfill_column_for_type_change_in_background
      #
      def backfill_columns_for_type_change_in_background(table_name, *column_names, model_name: nil,
                                                         type_cast_functions: {}, **options)
        if model_name.nil? && Utils.multiple_databases?
          raise ArgumentError, "You must pass a :model_name when using multiple databases."
        end

        tmp_columns = column_names.map { |column_name| "#{column_name}_for_type_change" }

        if model_name
          model_name = model_name.name if model_name.is_a?(Class)
          connection_class_name = Utils.find_connection_class(model_name.constantize).name
        end

        # model_name = model_name.name if model_name.is_a?(Class)
        # connection_class = Utils.find_connection_class(model_name.constantize) if model_name

        enqueue_background_data_migration(
          "CopyColumn",
          table_name,
          column_names,
          tmp_columns,
          model_name,
          type_cast_functions,
          connection_class_name: connection_class_name,
          **options
        )
      end

      # Copies data from the old column to the new column using background migrations.
      #
      # @param table_name [String, Symbol]
      # @param copy_from [String, Symbol] source column name
      # @param copy_to [String, Symbol] destination column name
      # @param model_name [String] If Active Record multiple databases feature is used,
      #     the class name of the model to get connection from.
      # @param type_cast_function [String, Symbol] Some type changes require casting data to a new type.
      #     For example when changing from `text` to `jsonb`. In this case, use the `type_cast_function` option.
      #     You need to make sure there is no bad data and the cast will always succeed
      # @param options [Hash] used to control the behavior of background migration.
      #     See `#enqueue_background_data_migration`
      #
      # @return [OnlineMigrations::BackgroundDataMigrations::Migration]
      #
      # @example
      #   copy_column_in_background(:users, :id, :id_for_type_change)
      #
      # @note This method is better suited for large tables (10/100s of millions of records).
      #     For smaller tables it is probably better and easier to use more flexible `update_column_in_batches`.
      #
      def copy_column_in_background(table_name, copy_from, copy_to, model_name: nil, type_cast_function: nil, **options)
        copy_columns_in_background(
          table_name,
          [copy_from],
          [copy_to],
          model_name: model_name,
          type_cast_functions: { copy_from => type_cast_function },
          **options
        )
      end

      # Same as `copy_column_in_background` but for multiple columns.
      #
      # @param type_cast_functions [Hash] if not empty, keys - column names,
      #   values - corresponding type cast functions
      #
      # @see #copy_column_in_background
      #
      def copy_columns_in_background(table_name, copy_from, copy_to, model_name: nil, type_cast_functions: {}, **options)
        if model_name.nil? && Utils.multiple_databases?
          raise ArgumentError, "You must pass a :model_name when using multiple databases."
        end

        model_name = model_name.name if model_name.is_a?(Class)

        enqueue_background_data_migration(
          "CopyColumn",
          table_name,
          copy_from,
          copy_to,
          model_name,
          type_cast_functions,
          **options
        )
      end

      # Resets one or more counter caches to their correct value using background migrations.
      # This is useful when adding new counter caches, or if the counter has been corrupted or modified directly by SQL.
      #
      # @param model_name [String]
      # @param counters [Array]
      # @param touch [Boolean, Symbol, Array] touch timestamp columns when updating.
      #   - when `true` - will touch `updated_at` and/or `updated_on`
      #   - when `Symbol` or `Array` - will touch specific column(s)
      # @param options [Hash] used to control the behavior of background migration.
      #     See `#enqueue_background_data_migration`
      #
      # @return [OnlineMigrations::BackgroundDataMigrations::Migration]
      #
      # @example
      #     reset_counters_in_background("User", :projects, :friends, touch: true)
      #
      # @example Touch specific column
      #     reset_counters_in_background("User", :projects, touch: :touched_at)
      #
      # @example Touch with specific time value
      #     reset_counters_in_background("User", :projects, touch: [time: 2.days.ago])
      #
      # @see https://api.rubyonrails.org/classes/ActiveRecord/CounterCache/ClassMethods.html#method-i-reset_counters
      #
      # @note This method is better suited for large tables (10/100s of millions of records).
      #     For smaller tables it is probably better and easier to use `reset_counters` from the Active Record.
      #
      def reset_counters_in_background(model_name, *counters, touch: nil, **options)
        model_name = model_name.name if model_name.is_a?(Class)

        enqueue_background_data_migration(
          "ResetCounters",
          model_name,
          counters,
          { touch: touch },
          **options
        )
      end

      # Deletes records with one or more missing relations using background migrations.
      # This is useful when some referential integrity in the database is broken and
      # you want to delete orphaned records.
      #
      # @param model_name [String]
      # @param associations [Array]
      # @param options [Hash] used to control the behavior of background migration.
      #     See `#enqueue_background_data_migration`
      #
      # @return [OnlineMigrations::BackgroundDataMigrations::Migration]
      #
      # @example
      #     delete_orphaned_records_in_background("Post", :author)
      #
      # @note This method is better suited for large tables (10/100s of millions of records).
      #     For smaller tables it is probably better and easier to directly find and delete orpahed records.
      #
      def delete_orphaned_records_in_background(model_name, *associations, **options)
        model_name = model_name.name if model_name.is_a?(Class)

        enqueue_background_data_migration(
          "DeleteOrphanedRecords",
          model_name,
          associations,
          **options
        )
      end

      # Deletes associated records for a specific parent record using background migrations.
      # This is useful when you are planning to remove a parent object (user, account etc)
      # and needs to remove lots of its associated objects.
      #
      # @param model_name [String]
      # @param record_id [Integer, String] parent record primary key's value
      # @param association [String, Symbol] association name for which records will be removed
      # @param options [Hash] used to control the behavior of background migration.
      #     See `#enqueue_background_data_migration`
      #
      # @return [OnlineMigrations::BackgroundDataMigrations::Migration]
      #
      # @example
      #     delete_associated_records_in_background("Link", 1, :clicks)
      #
      # @note This method is better suited for large tables (10/100s of millions of records).
      #     For smaller tables it is probably better and easier to directly delete associated records.
      #
      def delete_associated_records_in_background(model_name, record_id, association, **options)
        model_name = model_name.name if model_name.is_a?(Class)

        enqueue_background_data_migration(
          "DeleteAssociatedRecords",
          model_name,
          record_id,
          association,
          **options
        )
      end

      # Performs specific action on a relation or individual records.
      # This is useful when you want to delete/destroy/update/etc records based on some conditions.
      #
      # @param model_name [String]
      # @param conditions [Array, Hash, String] conditions to filter the relation
      # @param action [String, Symbol] action to perform on the relation or individual records.
      #     Relation-wide available actions: `:delete_all`, `:destroy_all`, and `:update_all`.
      # @param updates [Hash] updates to perform when `action` is set to `:update_all`
      # @param options [Hash] used to control the behavior of background migration.
      #     See `#enqueue_background_data_migration`
      #
      # @return [OnlineMigrations::BackgroundDataMigrations::Migration]
      #
      # @example Delete records
      #     perform_action_on_relation_in_background("User", { banned: true }, :delete_all)
      #
      # @example Destroy records
      #     perform_action_on_relation_in_background("User", { banned: true }, :destroy_all)
      #
      # @example Update records
      #     perform_action_on_relation_in_background("User", { banned: nil }, :update_all, updates: { banned: false })
      #
      # @example Perform custom method on individual records
      #     class User < ApplicationRecord
      #       def generate_invite_token
      #         self.invite_token = # some complex logic
      #       end
      #     end
      #
      #     perform_action_on_relation_in_background("User", { invite_token: nil }, :generate_invite_token)
      #
      # @note This method is better suited for large tables (10/100s of millions of records).
      #     For smaller tables it is probably better and easier to directly perform the action on associated records.
      #
      def perform_action_on_relation_in_background(model_name, conditions, action, updates: nil, **options)
        model_name = model_name.name if model_name.is_a?(Class)

        enqueue_background_data_migration(
          "PerformActionOnRelation",
          model_name,
          conditions,
          action,
          { updates: updates },
          **options
        )
      end

      # Creates a background migration for the given job class name.
      #
      # A background migration runs one job at a time, computing the bounds of the next batch
      # based on the current migration settings and the previous batch bounds. Each job's execution status
      # is tracked in the database as the migration runs.
      #
      # @param migration_name [String, Class] Background migration class name
      # @param arguments [Array] Extra arguments to pass to the migration instance when the migration runs
      # @param delay [Boolean] Whether this migration should be delayed and approved by the user to start running.
      # @option options [Integer] :max_attempts (5) Maximum number of batch run attempts
      # @option options [String, nil] :connection_class_name Class name to use to get connections
      #
      # @return [OnlineMigrations::BackgroundDataMigrations::Migration]
      #
      # @example
      #   enqueue_background_data_migration("BackfillProjectIssuesCount")
      #
      #   # Given the background migration exists:
      #
      #   class BackfillProjectIssuesCount < OnlineMigrations::DataMigration
      #     def collection
      #       Project.in_batches(of: 100)
      #     end
      #
      #     def process(projects)
      #       projects.update_all(
      #         "issues_count = (SELECT COUNT(*) FROM issues WHERE issues.project_id = projects.id)"
      #       )
      #     end
      #
      #     # To be able to track progress, you need to define this method.
      #     def count
      #       Project.maximum(:id)
      #     end
      #   end
      #
      # @note For convenience, the enqueued background data migration is run inline
      #     in development and test environments
      #
      def enqueue_background_data_migration(migration_name, *arguments, delay: false, **options)
        options.assert_valid_keys(:max_attempts, :iteration_pause, :connection_class_name)

        migration_name = migration_name.name if migration_name.is_a?(Class)
        options[:connection_class_name] ||= compute_connection_class_name(migration_name, arguments)

        if Utils.multiple_databases? && !options[:connection_class_name]
          raise ArgumentError, "You must pass a :connection_class_name when using multiple databases."
        end

        connection_class = options[:connection_class_name].constantize
        shards = Utils.shard_names(connection_class)
        shards = [nil] if shards.size == 1
        status = delay ? :delayed : :pending

        shards.each do |shard|
          # Can't use `find_or_create_by` or hash syntax here, because it does not correctly work with json `arguments`.
          migration = Migration.where(migration_name: migration_name, shard: shard).where("arguments = ?", arguments.to_json).first
          migration ||= Migration.create!(**options, status: status, migration_name: migration_name, arguments: arguments, shard: shard)

          if Utils.run_background_migrations_inline? && !migration.succeeded?
            migration.update_column(:status, :enqueued) if !migration.enqueued?
            job = OnlineMigrations.config.background_data_migrations.job
            job.constantize.perform_inline(migration.id)
          end
        end

        true
      end
      alias enqueue_background_migration enqueue_background_data_migration

      # Removes the background migration for the given class name and arguments, if exists.
      #
      # @param migration_name [String, Class] Background migration job class name
      # @param arguments [Array] Extra arguments the migration was originally created with
      #
      # @example
      #   remove_background_data_migration("BackfillProjectIssuesCount")
      #
      def remove_background_data_migration(migration_name, *arguments)
        migration_name = migration_name.name if migration_name.is_a?(Class)
        Migration.for_configuration(migration_name, arguments).delete_all
      end
      alias remove_background_migration remove_background_data_migration

      # Ensures that the background data migration with the provided configuration succeeded.
      #
      # If the enqueued migration was not found in development (probably when resetting a dev environment
      # followed by `db:migrate`), then a log warning is printed.
      # If enqueued migration was not found in production, then the error is raised.
      # If enqueued migration was found but is not succeeded, then the error is raised.
      #
      # @param migration_name [String, Class] Background migration job class name
      # @param arguments [Array, nil] Arguments with which background migration was enqueued
      #
      # @example Without arguments
      #   ensure_background_data_migration_succeeded("BackfillProjectIssuesCount")
      #
      # @example With arguments
      #   ensure_background_data_migration_succeeded("CopyColumn", arguments: ["users", "id", "id_for_type_change"])
      #
      def ensure_background_data_migration_succeeded(migration_name, arguments: nil)
        migration_name = migration_name.name if migration_name.is_a?(Class)

        configuration = { migration_name: migration_name }

        if arguments
          arguments = Array(arguments)
          migrations = Migration.for_configuration(migration_name, arguments).to_a
          configuration[:arguments] = arguments.to_json
        else
          migrations = Migration.for_migration_name(migration_name).to_a
        end

        if migrations.empty?
          Utils.raise_in_prod_or_say_in_dev("Could not find background data migration(s) for the given configuration: #{configuration}.")
        elsif !migrations.all?(&:succeeded?)
          raise "Expected background data migration(s) for the given configuration to be marked as 'succeeded': #{configuration}."
        end
      end
      alias ensure_background_migration_succeeded ensure_background_data_migration_succeeded

      private
        def compute_connection_class_name(migration_name, arguments)
          klass = DataMigration.named(migration_name)
          data_migration = klass.new(*arguments)

          collection = data_migration.collection

          model =
            case collection
            when ActiveRecord::Relation then collection.model
            when ActiveRecord::Batches::BatchEnumerator then collection.relation.model
            end

          if model
            connection_class = Utils.find_connection_class(model)
            connection_class.name
          end
        rescue NotImplementedError
          nil
        end
    end
  end
end
