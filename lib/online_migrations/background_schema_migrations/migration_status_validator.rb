# frozen_string_literal: true

module OnlineMigrations
  module BackgroundSchemaMigrations
    # @private
    class MigrationStatusValidator < ActiveModel::Validator
      VALID_STATUS_TRANSITIONS = {
        # enqueued -> running occurs when the migration starts performing.
        "enqueued" => ["running", "cancelled"],
        # running -> succeeded occurs when the migration completes successfully.
        # running -> errored occurs when the migration raised an error during the last run.
        # running -> failed occurs when the migration raises an error when running and retry attempts exceeded.
        "running" => ["succeeded", "errored", "failed", "cancelled"],
        # errored -> running occurs when previously errored migration starts running
        # errored -> failed occurs when the migration raises an error when running and retry attempts exceeded.
        "errored" => ["running", "failed", "cancelled"],
        # failed -> enqueued occurs when the failed migration is enqueued to be retried.
        # failed -> running occurs when the failed migration is retried.
        "failed" => ["enqueued", "running", "cancelled"],
      }

      def validate(record)
        return if !record.status_changed?

        previous_status, new_status = record.status_change
        valid_new_statuses = VALID_STATUS_TRANSITIONS.fetch(previous_status, [])

        if !valid_new_statuses.include?(new_status)
          record.errors.add(
            :status,
            "cannot transition background schema migration from status #{previous_status} to #{new_status}"
          )
        end
      end
    end
  end
end
