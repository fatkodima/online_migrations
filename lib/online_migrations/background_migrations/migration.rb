# frozen_string_literal: true

module OnlineMigrations
  module BackgroundMigrations
    # Class representing background data migration.
    #
    # @note The records of this class should not be created manually, but via
    #   `enqueue_background_data_migration` helper inside migrations.
    #
    class Migration < ApplicationRecord
      STATUSES = [
        :enqueued,    # The migration has been enqueued by the user.
        :running,     # The migration is being performed by a migration executor.
        :paused,      # The migration was paused in the middle of the run by the user.
        :finishing,   # The migration is being manually finishing inline by the user.
        :failed,      # The migration raises an exception when running.
        :succeeded,   # The migration finished without error.
        :cancelled,   # The migration was cancelled by the user.
      ]

      self.table_name = :background_migrations

      scope :queue_order, -> { order(created_at: :asc) }
      scope :parents, -> { where(parent_id: nil) }
      scope :runnable, -> { where(composite: false) }
      scope :active, -> { where(status: [statuses[:enqueued], statuses[:running]]) }
      scope :except_succeeded, -> { where.not(status: :succeeded) }
      scope :for_migration_name, ->(migration_name) { where(migration_name: normalize_migration_name(migration_name)) }
      scope :for_configuration, ->(migration_name, arguments) do
        for_migration_name(migration_name).where("arguments = ?", arguments.to_json)
      end

      alias_attribute :name, :migration_name

      enum :status, STATUSES.index_with(&:to_s)

      belongs_to :parent, class_name: name, optional: true, inverse_of: :children
      has_many :children, class_name: name, foreign_key: :parent_id, dependent: :delete_all, inverse_of: :parent
      has_many :migration_jobs, dependent: :delete_all, inverse_of: :migration

      validates :migration_name, :batch_column_name, presence: true

      validates :batch_size, :sub_batch_size, presence: true, numericality: { greater_than: 0 }
      validates :min_value, :max_value, presence: true, numericality: { greater_than: 0, unless: :composite? }

      validates :batch_pause, :sub_batch_pause_ms, presence: true,
                  numericality: { greater_than_or_equal_to: 0 }
      validates :rows_count, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true, unless: :composite?
      validates :arguments, uniqueness: { scope: [:migration_name, :shard] }

      validate :validate_batch_column_values
      validate :validate_batch_sizes
      validate :validate_jobs_status, if: :status_changed?

      validates_with BackgroundMigrationClassValidator
      validates_with MigrationStatusValidator, on: :update

      before_validation :set_defaults
      before_update :copy_attributes_to_children, if: :composite?

      # @private
      def self.normalize_migration_name(migration_name)
        namespace = ::OnlineMigrations.config.background_migrations.migrations_module
        migration_name.sub(/^(::)?#{namespace}::/, "")
      end

      def migration_name=(class_name)
        class_name = class_name.name if class_name.is_a?(Class)
        write_attribute(:migration_name, self.class.normalize_migration_name(class_name))
      end
      alias name= migration_name=

      def completed?
        succeeded? || failed?
      end

      # Overwrite enum's generated method to correctly work for composite migrations.
      def paused!
        return super if !composite?

        transaction do
          super
          children.each { |child| child.paused! if child.enqueued? || child.running? }
        end
      end

      # Overwrite enum's generated method to correctly work for composite migrations.
      def running!
        return super if !composite?

        transaction do
          super
          children.each { |child| child.running! if child.paused? }
        end
      end

      # Overwrite enum's generated method to correctly work for composite migrations.
      def cancelled!
        return super if !composite?

        transaction do
          super
          children.each { |child| child.cancelled! if !child.succeeded? }
        end
      end
      alias cancel cancelled!

      def pausable?
        true
      end

      def can_be_paused?
        enqueued? || running?
      end

      def can_be_cancelled?
        !succeeded? && !cancelled?
      end

      def last_job
        migration_jobs.order(:max_value).last
      end

      # Returns the progress of the background migration.
      #
      # @return [Float, nil]
      #   - when background migration is configured to not track progress, returns `nil`
      #   - otherwise returns value in range from 0.0 to 100.0
      #
      def progress
        if succeeded?
          100.0
        elsif enqueued?
          0.0
        elsif composite?
          rows_counts = children.to_a.pluck(:rows_count)
          if rows_counts.none?(nil)
            total_rows_count = rows_counts.sum
            return 100.0 if total_rows_count == 0

            progresses = children.map do |child|
              child.progress * child.rows_count / total_rows_count # weighted progress
            end

            progresses.sum.round(2)
          end
        elsif rows_count
          if rows_count > 0 && rows_count > batch_size
            jobs_rows_count = migration_jobs.succeeded.sum(:batch_size)
            # The last migration job may need to process the amount of rows
            # less than the batch size, so we can get a value > 1.0.
            ([jobs_rows_count.to_f / rows_count, 1.0].min * 100).round(2)
          else
            0.0
          end
        end
      end

      def migration_class
        BackgroundMigration.named(migration_name)
      end

      def migration_object
        @migration_object ||= migration_class.new(*arguments)
      end

      def migration_relation
        migration_object.relation
      end

      def migration_model
        migration_relation.model
      end

      # Returns whether the interval between previous step run has passed.
      # @return [Boolean]
      #
      def interval_elapsed?
        last_job = migration_jobs.order(:updated_at).last
        return true if last_job.nil?

        last_job.enqueued? || (last_job.updated_at + batch_pause <= Time.current)
      end

      # Mark this migration as ready to be processed again.
      #
      # This method marks failed jobs as ready to be processed again, and
      # they will be picked up on the next Scheduler run.
      #
      def retry
        if composite? && failed?
          transaction do
            enqueued!
            children.failed.each(&:retry)
          end

          true
        elsif failed?
          transaction do
            parent.enqueued! if parent
            enqueued!

            iterator = BatchIterator.new(migration_jobs.failed)
            iterator.each_batch(of: 100) do |batch|
              batch.each(&:retry)
            end
          end

          true
        else
          false
        end
      end
      alias retry_failed_jobs retry

      # Returns the time this migration started running.
      def started_at
        # To be precise, we should get the minimum of `started_at` amongst the children jobs
        # (for simple migrations) and amongst the children migrations (for composite migrations).
        # But we do not have an appropriate index on the jobs table and using this will lead to
        # N+1 queries if used inside some dashboard, for example.
        created_at
      end

      # Returns the time this migration finished running.
      def finished_at
        updated_at if completed?
      end

      # @private
      def on_shard(&block)
        abstract_class = Utils.find_connection_class(migration_model)

        shard = (self.shard || abstract_class.default_shard).to_sym
        abstract_class.connected_to(shard: shard, role: :writing, &block)
      end

      # @private
      def reset_failed_jobs_attempts
        iterator = BatchIterator.new(migration_jobs.failed)
        iterator.each_batch(of: 100) do |relation|
          relation.update_all(status: :enqueued, attempts: 0)
        end
      end

      # @private
      def next_batch_range
        iterator = BatchIterator.new(migration_relation)
        batch_range = nil

        on_shard do
          # rubocop:disable Lint/UnreachableLoop
          iterator.each_batch(of: batch_size, column: batch_column_name, start: next_min_value, finish: max_value) do |_relation, min_value, max_value|
            batch_range = [min_value, max_value]

            break
          end
          # rubocop:enable Lint/UnreachableLoop
        end

        return if batch_range.nil?

        min_value, max_value = batch_range
        return if min_value > self.max_value

        max_value = [max_value, self.max_value].min

        [min_value, max_value]
      end

      private
        def validate_batch_column_values
          if max_value.to_i < min_value.to_i
            errors.add(:base, "max_value should be greater than or equal to min_value")
          end
        end

        def validate_batch_sizes
          if sub_batch_size.to_i > batch_size.to_i
            errors.add(:base, "sub_batch_size should be smaller than or equal to batch_size")
          end
        end

        def validate_jobs_status
          if composite?
            if succeeded? && children.except_succeeded.exists?
              errors.add(:base, "all child migrations must be succeeded")
            elsif failed? && !children.failed.exists?
              errors.add(:base, "at least one child migration must be failed")
            end
          elsif succeeded? && migration_jobs.except_succeeded.exists?
            errors.add(:base, "all migration jobs must be succeeded")
          elsif failed? && !migration_jobs.failed.exists?
            errors.add(:base, "at least one migration job must be failed")
          end
        end

        def set_defaults
          if migration_relation.is_a?(ActiveRecord::Relation)
            self.batch_column_name ||= migration_relation.primary_key

            if composite?
              self.min_value = self.max_value = self.rows_count = -1 # not relevant
            else
              on_shard do
                # Getting exact min/max values can be a very heavy operation
                # and is not needed practically.
                self.min_value ||= 1
                self.max_value ||= migration_model.unscoped.maximum(batch_column_name) || self.min_value

                count = migration_object.count
                self.rows_count = count if count != :no_count
              end
            end
          end

          config = ::OnlineMigrations.config.background_migrations
          self.batch_size           ||= config.batch_size
          self.sub_batch_size       ||= config.sub_batch_size
          self.batch_pause          ||= config.batch_pause
          self.sub_batch_pause_ms   ||= config.sub_batch_pause_ms
          self.batch_max_attempts   ||= config.batch_max_attempts
        end

        def copy_attributes_to_children
          attributes = [:batch_size, :sub_batch_size, :batch_pause, :sub_batch_pause_ms, :batch_max_attempts]
          updates = {}
          attributes.each do |attribute|
            updates[attribute] = read_attribute(attribute) if attribute_changed?(attribute)
          end
          children.active.update_all(updates) if updates.any?
        end

        def next_min_value
          if last_job
            last_job.max_value.next
          else
            min_value
          end
        end
    end
  end
end
