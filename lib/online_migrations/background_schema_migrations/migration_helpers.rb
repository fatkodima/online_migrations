# frozen_string_literal: true

module OnlineMigrations
  module BackgroundSchemaMigrations
    module MigrationHelpers
      def add_index_in_background(table_name, column_name, **options)
        migration_options = options.extract!(:max_attempts, :statement_timeout, :connection_class_name)

        options[:algorithm] = :concurrently
        index, algorithm, if_not_exists = add_index_options(table_name, column_name, **options)

        # Need to check this first, because `index_exists?` does not check for `:where`s.
        if index_name_exists?(table_name, index.name)
          Utils.raise_or_say(<<~MSG)
            Index creation was not enqueued because the index with name '#{index.name}' already exists.
            This can be due to an aborted migration or you need to explicitly provide another name
            via `:name` option.
          MSG
          return
        end

        if index_exists?(table_name, column_name, name: index.name, **options)
          Utils.raise_or_say("Index creation was not enqueued because the index already exists.")
          return
        end

        create_index = ActiveRecord::ConnectionAdapters::CreateIndexDefinition.new(index, algorithm, if_not_exists)
        schema_creation = ActiveRecord::ConnectionAdapters::PostgreSQL::SchemaCreation.new(self)
        definition = schema_creation.accept(create_index)

        enqueue_background_schema_migration("Add index #{index.name}", table_name, definition: definition, **migration_options)
      end

      def remove_index_in_background(table_name, column_name = nil, name:, **options)
        raise ArgumentError, "Index name must be specified" if name.blank?

        migration_options = options.extract!(:max_attempts, :statement_timeout, :connection_class_name)

        if !index_exists?(table_name, column_name, **options, name: name)
          Utils.raise_or_say("Index deletion was not enqueued because the index does not exist.")
          return
        end

        definition = "DROP INDEX CONCURRENTLY IF EXISTS #{quote_column_name(name)}"
        enqueue_background_schema_migration("Remove index #{name}", table_name, definition: definition, **migration_options)
      end

      def validate_foreign_key_in_background(from_table, to_table = nil, **options)
        migration_options = options.extract!(:max_attempts, :statement_timeout, :connection_class_name)

        if !foreign_key_exists?(from_table, to_table, **options)
          Utils.raise_or_say("Foreign key validation was not enqueued because the foreign key does not exist.")
          return
        end

        fk_name_to_validate = foreign_key_for!(from_table, to_table: to_table, **options).name
        validate_constraint_in_background(from_table, fk_name_to_validate, **migration_options)
      end

      def validate_constraint_in_background(table_name, constraint_name, **options)
        definition = <<~SQL.squish
          ALTER TABLE #{quote_table_name(table_name)}
          VALIDATE CONSTRAINT #{quote_table_name(constraint_name)}
        SQL
        enqueue_background_schema_migration("Validate #{constraint_name}", table_name, definition: definition, **options)
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
        migrations = Migration.where("migration_name ILIKE ?", "%#{migration_name}%").to_a

        if migrations.empty?
          Utils.raise_in_prod_or_say_in_dev("Could not find background schema migration(s): '#{migration_name}'.")
        elsif !migrations.all?(&:succeeded?)
          raise "Expected background schema migration(s) '#{migration_name}' to be marked as 'succeeded'."
        end
      end

      def enqueue_background_schema_migration(migration_name, table_name, connection_class_name: nil, **options)
        options.assert_valid_keys(:definition, :max_attempts, :statement_timeout)

        if Utils.multiple_databases? && !connection_class_name
          raise ArgumentError, "You must pass a :connection_class_name when using multiple databases."
        end

        if connection_class_name
          klass = connection_class_name.constantize
          connection_class = Utils.find_connection_class(klass)
        else
          connection_class = ActiveRecord::Base
        end

        # Normalize to the real connection class name.
        connection_class_name = connection_class.name

        shards = Utils.shard_names(connection_class)
        shards = [nil] if shards.size == 1

        shards.each do |shard|
          migration = Migration.create_with(**options, table_name: table_name)
                               .find_or_create_by!(migration_name: migration_name, shard: shard, connection_class_name: connection_class_name)

          if Utils.run_background_migrations_inline?
            # Run migration again in development.
            migration.update_column(:status, :enqueued) if !migration.enqueued?

            runner = MigrationRunner.new(migration)
            runner.run
          end
        end

        true
      end
    end
  end
end
