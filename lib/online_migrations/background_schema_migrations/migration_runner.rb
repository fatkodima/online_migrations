# frozen_string_literal: true

module OnlineMigrations
  module BackgroundSchemaMigrations
    # Runs single background schema migration.
    class MigrationRunner
      attr_reader :migration

      def initialize(migration)
        @migration = migration
      end

      def run
        return if migration.cancelled? || migration.succeeded?

        migration.running! if migration.pending? || migration.errored?
        migration_payload = { migration: migration }

        if migration.attempts == 0
          ActiveSupport::Notifications.instrument("started.background_schema_migrations", migration_payload)
        else
          ActiveSupport::Notifications.instrument("retried.background_schema_migrations", migration_payload)
        end

        if should_throttle?
          ActiveSupport::Notifications.instrument("throttled.background_schema_migrations", migration_payload)
          return
        end

        migration.update!(
          attempts: migration.attempts + 1,
          status: :running,
          started_at: Time.current,
          finished_at: nil,
          error_class: nil,
          error_message: nil,
          backtrace: nil
        )

        ActiveSupport::Notifications.instrument("run.background_schema_migrations", migration_payload) do
          migration.run
        end

        # Background schema migrations could take a while to run. It is possible, that the process
        # never reaches this (or the rescue below) line of code. E.g., when it is force quitted
        # (SIGKILL etc.) and so the migration will end up in the "running" state and the query is
        # still executing (or already finished) in the database. This migration can either be safely
        # manually retried or will be picked up in the future by scheduler when it decides that
        # this migration is stuck.

        migration.update!(status: :succeeded, finished_at: Time.current)

        ActiveSupport::Notifications.instrument("completed.background_schema_migrations", migration_payload)
      rescue Exception => e # rubocop:disable Lint/RescueException
        backtrace_cleaner = ::OnlineMigrations.config.backtrace_cleaner

        status = migration.attempts_exceeded? ? :failed : :errored

        migration.update!(
          status: status,
          finished_at: Time.current,
          error_class: e.class.name,
          error_message: e.message,
          backtrace: backtrace_cleaner ? backtrace_cleaner.clean(e.backtrace) : e.backtrace
        )

        ::OnlineMigrations.config.background_schema_migrations.error_handler.call(e, migration)
        raise if Utils.run_background_migrations_inline?
      end

      private
        def should_throttle?
          ::OnlineMigrations.config.throttler.call
        end
    end
  end
end
