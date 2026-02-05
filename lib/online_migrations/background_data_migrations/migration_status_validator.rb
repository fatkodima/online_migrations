# frozen_string_literal: true

module OnlineMigrations
  module BackgroundDataMigrations
    # @private
    class MigrationStatusValidator < ActiveModel::Validator
      # Valid status transitions a Migration can make.
      VALID_STATUS_TRANSITIONS = {
        "pending" => ["enqueued", "paused", "cancelled"],
        # enqueued -> running occurs when the migration starts performing.
        # enqueued -> paused occurs when the migration is paused before starting.
        # enqueued -> cancelled occurs when the migration is cancelled before starting.
        # enqueued -> failed occurs when the migration job fails to be enqueued, or
        #   if the migration is deleted before is starts running.
        "enqueued" => ["running", "paused", "cancelled", "failed"],
        # running -> enqueued occurs when the migration is stuck and rescheduled by the scheduler.
        # running -> succeeded occurs when the migration completes successfully.
        # running -> pausing occurs when a user pauses the migration as it's performing.
        # running -> cancelling occurs when a user cancels the migration as it's performing.
        # running -> errored occurs when the migration raised an error during the last run.
        # running -> failed occurs when the migration raises an error when running and retry attempts exceeded.
        "running" => [
          "enqueued",
          "succeeded",
          "pausing",
          "cancelling",
          "errored",
          "failed",
        ],
        # pausing -> paused occurs when the migration actually halts performing and
        #   occupies a status of paused.
        # pausing -> cancelling occurs when the user cancels a migration immediately
        #   after it was paused, such that the migration had not actually halted yet.
        # pausing -> succeeded occurs when the migration completes immediately after
        #   being paused. This can happen if the migration is on its last iteration
        #   when it is paused, or if the migration is paused after enqueue but has
        #   nothing in its collection to process.
        # pausing -> failed occurs when the job raises an exception after the
        #   user has paused it.
        "pausing" => ["paused", "cancelling", "succeeded", "errored", "failed"],
        # paused -> pending occurs when the migration is resumed after being paused.
        # paused -> cancelled when the user cancels the migration after it is paused.
        "paused" => ["pending", "cancelled"],
        "errored" => ["running", "failed", "cancelled", "paused"],
        # failed -> pending occurs when the migration is retried after encounting an error.
        "failed" => ["pending"],
        # cancelling -> cancelled occurs when the migration actually halts performing
        #   and occupies a status of cancelled.
        # cancelling -> succeeded occurs when the migration completes immediately after
        #   being cancelled. See description for pausing -> succeeded.
        # cancelling -> failed occurs when the job raises an exception after the
        #   user has cancelled it.
        "cancelling" => ["cancelled", "succeeded", "errored", "failed"],
        # delayed -> pending occurs when the delayed migration was approved by the user to start running.
        # delayed -> cancelled occurs when the delayed migration was cancelled.
        "delayed" => ["pending", "cancelled"],
      }

      def validate(record)
        return if !record.status_changed?

        previous_status, new_status = record.status_change
        valid_new_statuses = VALID_STATUS_TRANSITIONS.fetch(previous_status, [])

        if !valid_new_statuses.include?(new_status)
          record.errors.add(
            :status,
            "cannot transition data migration from status '#{previous_status}' to '#{new_status}'"
          )
        end
      end
    end
  end
end
