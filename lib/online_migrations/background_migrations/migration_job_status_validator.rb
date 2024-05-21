# frozen_string_literal: true

module OnlineMigrations
  module BackgroundMigrations
    # @private
    class MigrationJobStatusValidator < ActiveModel::Validator
      VALID_STATUS_TRANSITIONS = {
        "enqueued" => ["running", "cancelled"],
        "running" => ["succeeded", "failed", "cancelled"],
        "failed" => ["enqueued", "running", "cancelled"],
      }

      def validate(record)
        return if !record.status_changed?

        previous_status, new_status = record.status_change
        valid_new_statuses = VALID_STATUS_TRANSITIONS.fetch(previous_status, [])

        if !valid_new_statuses.include?(new_status)
          record.errors.add(
            :status,
            "cannot transition background migration job from status #{previous_status} to #{new_status}"
          )
        end
      end
    end
  end
end
