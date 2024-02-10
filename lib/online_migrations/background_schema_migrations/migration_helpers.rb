# frozen_string_literal: true

module OnlineMigrations
  module BackgroundSchemaMigrations
    module MigrationHelpers
      def add_index_in_background(table_name, column_name, **options)
        migration_options = options.extract!(:max_attempts, :statement_timeout, :connection_class_name)

        if index_exists?(table_name, column_name, **options)
          Utils.raise_or_say("Index creation was not enqueued because the index already exists.")
          return
        end

        options[:algorithm] = :concurrently
        index, algorithm, if_not_exists = add_index_options(table_name, column_name, **options)

        create_index = ActiveRecord::ConnectionAdapters::CreateIndexDefinition.new(index, algorithm, if_not_exists)
        schema_creation = ActiveRecord::ConnectionAdapters::PostgreSQL::SchemaCreation.new(self)
        definition = schema_creation.accept(create_index)

        enqueue_background_schema_migration(index.name, table_name, definition: definition, **migration_options)
      end

      def remove_index_in_background(table_name, column_name = nil, name:, **options)
        raise ArgumentError, "Index name must be specified" if name.blank?

        migration_options = options.extract!(:max_attempts, :statement_timeout, :connection_class_name)

        if !index_exists?(table_name, column_name, **options, name: name)
          Utils.raise_or_say("Index deletion was not enqueued because the index does not exist.")
          return
        end

        definition = "DROP INDEX CONCURRENTLY IF EXISTS #{quote_column_name(name)}"
        enqueue_background_schema_migration(name, table_name, definition: definition, **migration_options)
      end

      # Ensures that the background schema migration with the provided migration name succeeded.
      #
      # If the enqueued migration was not found in development (probably when resetting a dev environment
      # followed by `db:migrate`), then a log warning is printed.
      # If enqueued migration was not found in production, then the error is raised.
      # If enqueued migration was found but is not succeeded, then the error is raised.
      #
      # @param migration_name [String, Symbol] Background schema migration name
      #
      # @example
      #   ensure_background_schema_migration_succeeded("index_users_on_email")
      #
      def ensure_background_schema_migration_succeeded(migration_name)
        migration = Migration.parents.find_by(migration_name: migration_name)

        if migration.nil?
          Utils.raise_in_prod_or_say_in_dev("Could not find background schema migration: '#{migration_name}'")
        elsif !migration.succeeded?
          raise "Expected background schema migration '#{migration_name}' to be marked as 'succeeded', " \
                "but it is '#{migration.status}'."
        end
      end

      def enqueue_background_schema_migration(name, table_name, **options)
        if options[:connection_class_name].nil? && Utils.multiple_databases?
          raise ArgumentError, "You must pass a :connection_class_name when using multiple databases."
        end

        migration = create_background_schema_migration(name, table_name, **options)

        run_inline = OnlineMigrations.config.run_background_migrations_inline
        if run_inline && run_inline.call
          runner = MigrationRunner.new(migration)
          runner.run
        end

        migration
      end

      # @private
      def create_background_schema_migration(migration_name, table_name, **options)
        options.assert_valid_keys(:definition, :max_attempts, :statement_timeout, :connection_class_name)
        migration = Migration.new(migration_name: migration_name, table_name: table_name, **options)

        shards = Utils.shard_names(migration.connection_class)
        if shards.size > 1
          migration.children = shards.map do |shard|
            child = migration.dup
            child.shard = shard
            child
          end

          migration.composite = true
        end

        # This will save all the records using a transaction.
        migration.save!
        migration
      end
    end
  end
end
