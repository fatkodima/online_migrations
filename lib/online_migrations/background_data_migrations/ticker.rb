# frozen_string_literal: true

module OnlineMigrations
  module BackgroundDataMigrations
    # This class encapsulates the logic behind updating the tick counter.
    #
    # It's initialized with a duration for the throttle, and a block to persist
    # the number of ticks to increment.
    #
    # When +tick+ is called, the block will be called with the increment,
    # provided the duration since the last update (or initialization) has been
    # long enough.
    #
    # To not lose any increments, +persist+ should be used, which may call the
    # block with any leftover ticks.
    #
    # @private
    class Ticker
      # Creates a Ticker that will call the block each time +tick+ is called,
      # unless the tick is being throttled.
      #
      # @param interval [ActiveSupport::Duration, Numeric] Duration
      #   since initialization or last call that will cause a throttle.
      # @yieldparam ticks [Integer] the increment in ticks to be persisted.
      #
      def initialize(interval, &block)
        @interval = interval
        @block = block
        @last_persisted_at = Time.current
        @ticks_recorded = 0
      end

      # Increments the tick count by one, and may persist the new value if the
      # threshold duration has passed since initialization or the tick count was
      # last persisted.
      #
      def tick
        @ticks_recorded += 1
        persist if persist?
      end

      # Persists the tick increments by calling the block passed to the
      # initializer. This is idempotent in the sense that calling it twice in a
      # row will call the block at most once (if it had been throttled).
      #
      def persist
        return if @ticks_recorded == 0

        now = Time.current
        duration = now - @last_persisted_at
        @last_persisted_at = now
        @block.call(@ticks_recorded, duration)
        @ticks_recorded = 0
      end

      private
        def persist?
          Time.now - @last_persisted_at >= @interval
        end
    end
  end
end
