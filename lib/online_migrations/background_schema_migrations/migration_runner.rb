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

        mark_as_running if migration.enqueued? || migration.errored?

        if migration.composite?
          migration.children.each do |child_migration|
            runner = self.class.new(child_migration)
            runner.run
          end
        else
          do_run
        end
      end

      private
        def mark_as_running
          Migration.transaction do
            migration.running!

            if (parent = migration.parent)
              if parent.started_at
                parent.update!(status: :running, finished_at: nil)
              else
                parent.update!(status: :running, started_at: Time.current, finished_at: nil)
              end
            end
          end
        end

        def do_run
          migration_payload = notifications_payload(migration)

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

          complete_parent_if_needed(migration) if migration.parent.present?
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

          complete_parent_if_needed(migration) if migration.parent.present?

          ::OnlineMigrations.config.background_schema_migrations.error_handler.call(e, migration)
          raise if Utils.run_background_migrations_inline?
        end

        def should_throttle?
          ::OnlineMigrations.config.throttler.call
        end

        def complete_parent_if_needed(migration)
          parent = migration.parent
          completed = false

          parent.with_lock do
            children = parent.children.select(:status)
            if children.all?(&:succeeded?)
              parent.update!(status: :succeeded, finished_at: Time.current)
              completed = true
            elsif children.any?(&:failed?)
              parent.update!(status: :failed, finished_at: Time.current)
              completed = true
            end
          end

          if completed
            ActiveSupport::Notifications.instrument("completed.background_migrations", notifications_payload(migration))
          end
        end

        def notifications_payload(migration)
          { background_schema_migration: migration }
        end
    end
  end
end
