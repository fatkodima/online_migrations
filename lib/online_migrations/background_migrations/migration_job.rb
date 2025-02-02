# frozen_string_literal: true

module OnlineMigrations
  module BackgroundMigrations
    class MigrationJob < ApplicationRecord
      STATUSES = [
        :enqueued,
        :running,
        :errored,
        :failed,
        :succeeded,
        :cancelled,
      ]

      self.table_name = :background_migration_jobs

      scope :active, -> { where(status: [:enqueued, :running, :errored]) }
      scope :completed, -> { where(status: [:failed, :succeeded]) }
      scope :stuck, -> do
        timeout = OnlineMigrations.config.background_migrations.stuck_jobs_timeout
        running.where("updated_at <= ?", timeout.seconds.ago)
      end

      scope :retriable, -> do
        stuck_sql = connection.unprepared_statement { stuck.to_sql }

        from(Arel.sql(<<~SQL))
          (
            (SELECT * FROM background_migration_jobs WHERE status = 'errored')
            UNION
            (#{stuck_sql})
          ) AS #{table_name}
        SQL
      end

      scope :except_succeeded, -> { where.not(status: :succeeded) }

      enum :status, STATUSES.index_with(&:to_s)

      delegate :migration_name, :migration_class, :migration_object, :migration_relation, :batch_column_name,
        :arguments, :batch_pause, to: :migration

      belongs_to :migration, inverse_of: :migration_jobs

      validates :min_value, :max_value, presence: true, numericality: { greater_than: 0 }
      validate :values_in_migration_range, if: :min_value?
      validate :validate_values_order, if: :min_value?

      validates_with MigrationJobStatusValidator, on: :update

      before_create :copy_settings_from_migration

      # Whether the job is considered stuck (is running for some configured time).
      #
      def stuck?
        timeout = OnlineMigrations.config.background_migrations.stuck_jobs_timeout
        running? && updated_at <= timeout.seconds.ago
      end

      def attempts_exceeded?
        attempts >= max_attempts
      end

      # Mark this job as ready to be processed again.
      #
      # This is used when retrying failed jobs.
      #
      def retry
        if failed?
          transaction do
            update!(
              status: self.class.statuses[:enqueued],
              attempts: 0,
              started_at: nil,
              finished_at: nil,
              error_class: nil,
              error_message: nil,
              backtrace: nil
            )
            migration.enqueued! if migration.failed?
          end
          true
        else
          false
        end
      end

      private
        def values_in_migration_range
          if min_value < migration.min_value || max_value > migration.max_value
            errors.add(:base, "min_value and max_value should be in background migration values range")
          end
        end

        def validate_values_order
          if max_value.to_i < min_value.to_i
            errors.add(:base, "max_value should be greater than or equal to min_value")
          end
        end

        def copy_settings_from_migration
          self.batch_size       = migration.batch_size
          self.sub_batch_size   = migration.sub_batch_size
          self.pause_ms         = migration.sub_batch_pause_ms
          self.max_attempts     = migration.batch_max_attempts
        end
    end
  end
end
