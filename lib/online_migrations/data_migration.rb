# frozen_string_literal: true

gem "sidekiq", ">= 7.3.3"
require "sidekiq"

module OnlineMigrations
  # Base class that is inherited by the host application's data migration classes.
  class DataMigration
    class NotFoundError < NameError; end

    class << self
      # Finds a Data Migration with the given name.
      #
      # @param name [String] the name of the Data Migration to be found.
      #
      # @return [DataMigration] the Data Migration with the given name.
      #
      # @raise [NotFoundError] if a Data Migration with the given name does not exist.
      #
      def named(name)
        namespace = OnlineMigrations.config.background_data_migrations.migrations_module.constantize
        internal_namespace = ::OnlineMigrations::BackgroundDataMigrations

        migration = "#{namespace}::#{name}".safe_constantize ||
                    "#{internal_namespace}::#{name}".safe_constantize

        raise NotFoundError.new("Data Migration #{name} not found", name) if migration.nil?
        if !(migration.is_a?(Class) && migration < self)
          raise NotFoundError.new("#{name} is not a Data Migration", name)
        end

        migration
      end

      # @private
      attr_accessor :active_record_enumerator_batch_size

      # Limit the number of records that will be fetched in a single query when
      # iterating over an Active Record collection migration.
      #
      # @param size [Integer] the number of records to fetch in a single query.
      #
      def collection_batch_size(size)
        self.active_record_enumerator_batch_size = size
      end
    end

    # A hook to override that will be called when the migration starts running.
    #
    def after_start
    end

    # A hook to override that will be called around 'process' each time.
    #
    # Can be useful for some metrics collection, performance tracking etc.
    #
    def around_process
      yield
    end

    # A hook to override that will be called when the migration resumes its work.
    #
    def after_resume
    end

    # A hook to override that will be called each time the migration is interrupted.
    #
    # This can be due to interruption or sidekiq stopping.
    #
    def after_stop
    end

    # A hook to override that will be called when the migration finished its work.
    #
    def after_complete
    end

    # A hook to override that will be called when the migration is paused.
    #
    def after_pause
    end

    # A hook to override that will be called when the migration is cancelled.
    #
    def after_cancel
    end

    # The collection to be processed.
    #
    # @return [ActiveRecord::Relation, ActiveRecord::Batches::BatchEnumerator, Array, Enumerator]
    #
    # @raise [NotImplementedError] with a message advising subclasses to override this method.
    #
    def collection
      raise NotImplementedError, "#{self.class.name} must implement a 'collection' method"
    end

    # The action to be performed on each item from the collection.
    #
    # @param _item the current item from the collection being iterated
    # @raise [NotImplementedError] with a message advising subclasses to override this method.
    #
    def process(_item)
      raise NotImplementedError, "#{self.class.name} must implement a 'process' method"
    end

    # Total count of iterations to be performed (optional, to be able to show progress).
    #
    # @return [Integer, nil]
    #
    def count
    end

    # Enumerator builder. You may override this method to return any Enumerator yielding
    # pairs of `[item, item_cursor]`, instead of using `collection`.
    #
    # It is useful when it is not practical or impossible to define an explicit collection
    # in the `collection` method.
    #
    # @param cursor [Object, nil] cursor position to resume from, or nil on initial call.
    #
    # @return [Enumerator]
    #
    def build_enumerator(cursor:)
    end
  end
end
