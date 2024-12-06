# frozen_string_literal: true

module OnlineMigrations
  # This class provides a way to automatically retry code that relies on acquiring
  # a database lock in a way designed to minimize impact on a busy production database.
  #
  # This class defines an interface for child classes to implement to configure
  # timing configurations and the maximum number of attempts.
  #
  # There are two predefined implementations (see OnlineMigrations::ConstantLockRetrier and OnlineMigrations::ExponentialLockRetrier).
  # It is easy to provide more sophisticated implementations.
  #
  # @example Custom LockRetrier implementation
  #   module OnlineMigrations
  #     class SophisticatedLockRetrier < LockRetrier
  #       TIMINGS = [
  #         [0.1.seconds, 0.05.seconds], # first - lock timeout, second - delay time
  #         [0.1.seconds, 0.05.seconds],
  #         [0.2.seconds, 0.05.seconds],
  #         [0.3.seconds, 0.10.seconds],
  #         [1.second, 5.seconds],
  #         [1.second, 1.minute],
  #         [0.1.seconds, 0.05.seconds],
  #         [0.2.seconds, 0.15.seconds],
  #         [0.5.seconds, 2.seconds],
  #         [0.5.seconds, 2.seconds],
  #         [3.seconds, 3.minutes],
  #         [0.1.seconds, 0.05.seconds],
  #         [0.5.seconds, 2.seconds],
  #         [5.seconds, 2.minutes],
  #         [7.seconds, 5.minutes],
  #         [0.5.seconds, 2.seconds],
  #       ]
  #
  #       def attempts
  #         TIMINGS.size
  #       end
  #
  #       def lock_timeout(attempt)
  #         TIMINGS[attempt - 1][0]
  #       end
  #
  #       def delay(attempt)
  #         TIMINGS[attempt - 1][1]
  #       end
  #     end
  #
  class LockRetrier
    # Database connection on which retries are run
    #
    attr_accessor :connection

    # Returns the number of retrying attempts
    #
    def attempts
      raise NotImplementedError
    end

    # Returns database lock timeout value (in seconds) for specified attempt number
    #
    # @param _attempt [Integer] attempt number
    #
    def lock_timeout(_attempt); end

    # Returns sleep time after unsuccessful lock attempt (in seconds)
    #
    # @param _attempt [Integer] attempt number
    #
    def delay(_attempt)
      raise NotImplementedError
    end

    # Executes the block with a retry mechanism that alters the `lock_timeout`
    # and sleep time between attempts.
    #
    # @return [void]
    #
    # @example
    #   retrier.with_lock_retries do
    #     add_column(:users, :name, :string)
    #   end
    #
    def with_lock_retries(&block)
      return yield if lock_retries_disabled?

      current_attempt = 0

      begin
        current_attempt += 1

        current_lock_timeout = lock_timeout(current_attempt)
        if current_lock_timeout
          with_lock_timeout(current_lock_timeout.in_milliseconds, &block)
        else
          yield
        end
      rescue ActiveRecord::LockWaitTimeout
        if current_attempt <= attempts
          current_delay = delay(current_attempt)
          Utils.say("Lock timeout. Retrying in #{current_delay} seconds...")
          sleep(current_delay)
          retry
        end
        raise
      end
    end

    private
      def lock_retries_disabled?
        Utils.to_bool(ENV["DISABLE_LOCK_RETRIES"])
      end

      def with_lock_timeout(value)
        value = value.ceil.to_i
        prev_value = connection.select_value("SHOW lock_timeout")
        connection.execute("SET lock_timeout TO #{connection.quote("#{value}ms")}")

        yield
      ensure
        connection.execute("SET lock_timeout TO #{connection.quote(prev_value)}")
      end
  end

  # `LockRetrier` implementation that has a constant delay between tries
  # and lock timeout for each try
  #
  # @example
  #   # This will attempt 5 retries with 2 seconds between each unsuccessful try
  #   # and 50ms set as lock timeout for each try:
  #   config.retrier = OnlineMigrations::ConstantLockRetrier.new(attempts: 5, delay: 2.seconds, lock_timeout: 0.05.seconds)
  #
  class ConstantLockRetrier < LockRetrier
    # LockRetrier API implementation
    #
    # @return [Integer] Number of retrying attempts
    # @see LockRetrier#attempts
    #
    attr_reader :attempts

    # Create a new ConstantLockRetrier instance
    #
    # @param attempts [Integer] Maximum number of attempts
    # @param delay [Numeric] Sleep time after unsuccessful lock attempt (in seconds)
    # @param lock_timeout [Numeric, nil] Database lock timeout value (in seconds)
    #
    def initialize(attempts:, delay:, lock_timeout: nil)
      super()
      @attempts = attempts
      @delay = delay
      @lock_timeout = lock_timeout
    end

    # LockRetrier API implementation
    #
    # @return [Numeric] Database lock timeout value (in seconds)
    # @see LockRetrier#lock_timeout
    #
    def lock_timeout(_attempt)
      @lock_timeout
    end

    # LockRetrier API implementation
    #
    # @return [Numeric] Sleep time after unsuccessful lock attempt (in seconds)
    # @see LockRetrier#delay
    #
    def delay(_attempt)
      @delay
    end
  end

  # `LockRetrier` implementation that uses exponential delay with jitter between tries
  # and constant lock timeout for each try
  #
  # @example
  #   # This will attempt 30 retries starting with delay of 10ms between each unsuccessful try, increasing exponentially
  #   # up to the maximum delay of 1 minute and 200ms set as lock timeout for each try:
  #
  #   config.retrier = OnlineMigrations::ExponentialLockRetrier.new(attempts: 30,
  #       base_delay: 0.01.seconds, max_delay: 1.minute, lock_timeout: 0.2.seconds)
  #
  class ExponentialLockRetrier < LockRetrier
    # LockRetrier API implementation
    #
    # @return [Integer] Number of retrying attempts
    # @see LockRetrier#attempts
    #
    attr_reader :attempts

    # Create a new ExponentialLockRetrier instance
    #
    # @param attempts [Integer] Maximum number of attempts
    # @param base_delay [Numeric] Base sleep time to calculate total sleep time after unsuccessful lock attempt (in seconds)
    # @param max_delay [Numeric] Maximum sleep time after unsuccessful lock attempt (in seconds)
    # @param lock_timeout [Numeric] Database lock timeout value (in seconds)
    #
    def initialize(attempts:, base_delay:, max_delay:, lock_timeout: nil)
      super()
      @attempts = attempts
      @base_delay = base_delay
      @max_delay = max_delay
      @lock_timeout = lock_timeout
    end

    # LockRetrier API implementation
    #
    # @return [Numeric] Database lock timeout value (in seconds)
    # @see LockRetrier#lock_timeout
    #
    def lock_timeout(_attempt)
      @lock_timeout
    end

    # LockRetrier API implementation
    #
    # @return [Numeric] Sleep time after unsuccessful lock attempt (in seconds)
    # @see LockRetrier#delay
    # @see https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/
    #
    def delay(attempt)
      (rand * [@max_delay, @base_delay * (2**(attempt - 1))].min).ceil
    end
  end

  # @private
  class NullLockRetrier < LockRetrier
    def attempts(*)
      0
    end

    def lock_timeout(*)
    end

    def delay(*)
    end

    def with_lock_retries
      yield
    end
  end
end
