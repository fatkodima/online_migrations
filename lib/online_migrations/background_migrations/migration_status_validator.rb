# frozen_string_literal: true

module OnlineMigrations
  module BackgroundMigrations
    # @private
    class MigrationStatusValidator < ActiveModel::Validator
      VALID_STATUS_TRANSITIONS = {
        # enqueued -> running occurs when the migration starts performing.
        # enqueued -> paused occurs when the migration is paused before starting.
        "enqueued" => ["running", "paused", "cancelled"],
        # running -> paused occurs when a user pauses the migration as
        #   it's performing.
        # running -> finishing occurs when a user manually finishes the migration.
        # running -> succeeded occurs when the migration completes successfully.
        # running -> failed occurs when the migration raises an exception when running.
        "running" => [
          "paused",
          "finishing",
          "succeeded",
          "failed",
          "cancelled",
        ],
        # finishing -> succeeded occurs when the migration completes successfully.
        # finishing -> failed occurs when the migration raises an exception when running.
        "finishing" => ["succeeded", "failed", "cancelled"],
        # paused -> running occurs when the migration is resumed after being paused.
        "paused" => ["running", "cancelled"],
        # failed -> enqueued occurs when the failed migration jobs are retried after being failed.
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
            "cannot transition background migration from status #{previous_status} to #{new_status}"
          )
        end
      end
    end
  end
end
