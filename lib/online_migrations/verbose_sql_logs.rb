# frozen_string_literal: true

module OnlineMigrations
  # @private
  module VerboseSqlLogs
    class << self
      def enable
        @activerecord_logger_was = ActiveRecord::Base.logger
        @verbose_query_logs_was = ActiveRecord.verbose_query_logs
        return if @activerecord_logger_was.nil?

        stdout_logger = ActiveSupport::Logger.new($stdout)
        stdout_logger.formatter = @activerecord_logger_was.formatter
        stdout_logger.level = @activerecord_logger_was.level
        stdout_logger = ActiveSupport::TaggedLogging.new(stdout_logger)

        combined_logger =
          # Broadcasting logs API was changed in https://github.com/rails/rails/pull/48615.
          if Utils.ar_version >= 7.1
            ActiveSupport::BroadcastLogger.new(stdout_logger, @activerecord_logger_was)
          else
            stdout_logger.extend(ActiveSupport::Logger.broadcast(@activerecord_logger_was))
          end

        ActiveRecord::Base.logger = combined_logger
        ActiveRecord.verbose_query_logs = false
      end

      def disable
        ActiveRecord::Base.logger = @activerecord_logger_was
        ActiveRecord.verbose_query_logs = @verbose_query_logs_was
      end
    end
  end
end
