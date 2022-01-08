# frozen_string_literal: true

module OnlineMigrations
  module BackgroundMigrations
    # @private
    class MigrationJobStatusValidator < ActiveModel::Validator
      VALID_STATUS_TRANSITIONS = {
        "enqueued" => ["running"],
        "running" => ["succeeded", "failed"],
        "failed" => ["enqueued", "running"],
      }

      def validate(record)
        return unless (previous_status, new_status = record.status_change)

        valid_new_statuses = VALID_STATUS_TRANSITIONS.fetch(previous_status, [])

        unless valid_new_statuses.include?(new_status)
          record.errors.add(
            :status,
            "cannot transition background migration job from status #{previous_status} to #{new_status}"
          )
        end
      end
    end
  end
end
