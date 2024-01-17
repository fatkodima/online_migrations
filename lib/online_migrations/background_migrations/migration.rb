# frozen_string_literal: true

module OnlineMigrations
  module BackgroundMigrations
    # Class representing background data migration.
    #
    # @note The records of this class should not be created manually, but via
    #   `enqueue_background_migration` helper inside migrations.
    #
    class Migration < ApplicationRecord
      STATUSES = [
        :enqueued,    # The migration has been enqueued by the user.
        :running,     # The migration is being performed by a migration executor.
        :paused,      # The migration was paused in the middle of the run by the user.
        :finishing,   # The migration is being manually finishing inline by the user.
        :failed,      # The migration raises an exception when running.
        :succeeded,   # The migration finished without error.
      ]

      self.table_name = :background_migrations

      scope :queue_order, -> { order(created_at: :asc) }
      scope :runnable, -> { where(composite: false) }
      scope :active, -> { where(status: [statuses[:enqueued], statuses[:running]]) }
      scope :except_succeeded, -> { where.not(status: :succeeded) }
      scope :for_migration_name, ->(migration_name) { where(migration_name: normalize_migration_name(migration_name)) }
      scope :for_configuration, ->(migration_name, arguments) do
        for_migration_name(migration_name).where("arguments = ?", arguments.to_json)
      end

      enum status: STATUSES.index_with(&:to_s)

      belongs_to :parent, class_name: name, optional: true
      has_many :children, class_name: name, foreign_key: :parent_id, dependent: :delete_all
      has_many :migration_jobs, dependent: :delete_all

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

      def last_job
        migration_jobs.order(:max_value).last
      end

      def last_completed_job
        migration_jobs.completed.order(:finished_at).last
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
        elsif composite?
          rows_counts = children.to_a.pluck(:rows_count)
          if rows_counts.none?(nil)
            total_rows_count = rows_counts.sum

            progresses = children.map do |child|
              child.progress * child.rows_count / total_rows_count # weighted progress
            end

            progresses.sum.round(2)
          end
        elsif rows_count
          jobs_rows_count = migration_jobs.succeeded.sum(:batch_size)
          # The last migration job may need to process the amount of rows
          # less than the batch size, so we can get a value > 1.0.
          ([jobs_rows_count.to_f / rows_count, 1.0].min * 100).round(2)
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
        last_active_job = migration_jobs.active.order(:updated_at).last

        if last_active_job && !last_active_job.stuck?
          false
        elsif batch_pause > 0 && (job = last_completed_job)
          job.finished_at + batch_pause <= Time.current
        else
          true
        end
      end

      # Manually retry failed jobs.
      #
      # This method marks failed jobs as ready to be processed again, and
      # they will be picked up on the next Scheduler run.
      #
      def retry_failed_jobs
        iterator = BatchIterator.new(migration_jobs.failed)
        iterator.each_batch(of: 100) do |batch|
          transaction do
            batch.each(&:retry)
            enqueued!
          end
        end
      end

      # @private
      def on_shard(&block)
        abstract_class = find_abstract_class(migration_model)

        shard = (self.shard || abstract_class.default_shard).to_sym
        abstract_class.connected_to(shard: shard, role: :writing, &block)
      end

      # @private
      def reset_failed_jobs_attempts
        iterator = BatchIterator.new(migration_jobs.failed.attempts_exceeded)
        iterator.each_batch(of: 100) do |relation|
          relation.update_all(attempts: 0)
        end
      end

      # @private
      def next_batch_range
        iterator = BatchIterator.new(migration_relation)
        batch_range = nil

        on_shard do
          # rubocop:disable Lint/UnreachableLoop
          iterator.each_batch(of: batch_size, column: batch_column_name, start: next_min_value) do |relation|
            min = relation.arel_table[batch_column_name].minimum
            max = relation.arel_table[batch_column_name].maximum
            batch_range = relation.pick(min, max)

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
                self.min_value ||= migration_relation.minimum(batch_column_name)
                self.max_value ||= migration_relation.maximum(batch_column_name)

                # This can be the case when run in development on empty tables
                if min_value.nil?
                  # integer IDs minimum value is 1
                  self.min_value = self.max_value = 1
                end

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

        def find_abstract_class(model)
          model.ancestors.find do |parent|
            parent == ActiveRecord::Base ||
              (parent.is_a?(Class) && parent.abstract_class?)
          end
        end
    end
  end
end
