# frozen_string_literal: true

module OnlineMigrations
  module BackgroundMigrations
    # @private
    class MigrationJobRunner
      attr_reader :migration_job

      delegate :migration, :attempts, :migration_relation, :migration_object, :sub_batch_size,
        :batch_column_name, :min_value, :max_value, :pause_ms, to: :migration_job

      def initialize(migration_job)
        @migration_job = migration_job
      end

      def run
        job_payload = { background_migration_job: migration_job }
        if migration_job.attempts >= 1
          ActiveSupport::Notifications.instrument("retried.background_migrations", job_payload)
        end

        migration_job.update!(
          attempts: attempts + 1,
          status: :running,
          started_at: Time.current,
          finished_at: nil,
          error_class: nil,
          error_message: nil,
          backtrace: nil
        )

        ActiveSupport::Notifications.instrument("process_batch.background_migrations", job_payload) do
          migration.on_shard { run_batch }
        end

        migration_job.update!(status: :succeeded, finished_at: Time.current)
      rescue Exception => e # rubocop:disable Lint/RescueException
        backtrace_cleaner = ::OnlineMigrations.config.background_migrations.backtrace_cleaner

        migration_job.update!(
          status: :failed,
          finished_at: Time.current,
          error_class: e.class.name,
          error_message: e.message,
          backtrace: backtrace_cleaner ? backtrace_cleaner.clean(e.backtrace) : e.backtrace
        )

        ::OnlineMigrations.config.background_migrations.error_handler.call(e, migration_job)
        raise if Utils.run_background_migrations_inline?
      end

      private
        def run_batch
          iterator = ::OnlineMigrations::BatchIterator.new(migration_relation)

          iterator.each_batch(of: sub_batch_size, column: batch_column_name,
                              start: min_value, finish: max_value) do |sub_batch|
            migration_object.process_batch(sub_batch)
            sleep(pause_ms * 0.001) if pause_ms > 0
          end
        end
    end
  end
end
