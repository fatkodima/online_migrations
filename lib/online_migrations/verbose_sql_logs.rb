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

        combined_logger = ActiveSupport::BroadcastLogger.new(stdout_logger, @activerecord_logger_was)

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
