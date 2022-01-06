# frozen_string_literal: true

module OnlineMigrations
  # @private
  module DatabaseTasks
    def migrate
      super
    rescue => e # rubocop:disable Style/RescueStandardError
      if e.cause.is_a?(OnlineMigrations::Error)
        # strip cause
        def e.cause
          nil
        end
      end

      raise e
    end
  end
end
