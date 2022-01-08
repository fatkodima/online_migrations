# frozen_string_literal: true

module OnlineMigrations
  # Base class that is inherited by the host application's background migration classes.
  class BackgroundMigration
    class NotFoundError < NameError; end

    class << self
      # Finds a Background Migration with the given name.
      #
      # @param name [String] the name of the Background Migration to be found.
      #
      # @return [BackgroundMigration] the Background Migration with the given name.
      #
      # @raise [NotFoundError] if a Background Migration with the given name does not exist.
      #
      def named(name)
        namespace = OnlineMigrations.config.background_migrations.migrations_module.constantize
        internal_namespace = ::OnlineMigrations::BackgroundMigrations

        migration = "#{namespace}::#{name}".safe_constantize ||
                    "#{internal_namespace}::#{name}".safe_constantize

        raise NotFoundError.new("Background Migration #{name} not found", name) unless migration
        unless migration.is_a?(Class) && migration < self
          raise NotFoundError.new("#{name} is not a Background Migration", name)
        end

        migration
      end
    end

    # The relation to be iterated over.
    #
    # @return [ActiveRecord::Relation]
    #
    # @raise [NotImplementedError] with a message advising subclasses to
    #     implement an override for this method.
    #
    def relation
      raise NotImplementedError, "#{self.class.name} must implement a 'relation' method"
    end

    # Processes one batch.
    #
    # @param _relation [ActiveRecord::Relation] the current batch from the enumerator being iterated
    # @return [void]
    #
    # @raise [NotImplementedError] with a message advising subclasses to
    #     implement an override for this method.
    #
    def process_batch(_relation)
      raise NotImplementedError, "#{self.class.name} must implement a 'process_batch' method"
    end

    # Returns the count of rows that will be iterated over (optional, to be able to show progress).
    #
    # @return [Integer, nil, :no_count]
    #
    def count
      :no_count
    end
  end
end
