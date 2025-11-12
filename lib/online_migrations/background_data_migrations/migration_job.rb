# frozen_string_literal: true

module OnlineMigrations
  module BackgroundDataMigrations
    # Sidekiq job responsible for running background data migrations.
    class MigrationJob
      include Sidekiq::IterableJob

      sidekiq_options backtrace: true

      sidekiq_retry_in do |count, _exception, jobhash|
        migration_id = jobhash["args"].fetch(0)
        migration = Migration.find(migration_id)

        if count + 1 >= migration.max_attempts
          :kill
        end
      end

      sidekiq_retries_exhausted do |jobhash, exception|
        migration_id = jobhash["args"].fetch(0)
        migration = Migration.find(migration_id)
        migration.persist_error(exception)

        OnlineMigrations.config.background_data_migrations.error_handler.call(exception, migration)
      end

      TICKER_INTERVAL = 5 # seconds

      def initialize
        super

        @migration = nil
        @data_migration = nil

        @ticker = Ticker.new(TICKER_INTERVAL) do |ticks, duration|
          # TODO: use 'cursor' accessor from sidekiq in the future.
          # https://github.com/sidekiq/sidekiq/pull/6606
          @migration.persist_progress(@_cursor, ticks, duration)

          # When using a scheduler, these are running only from a single shard, but when inline -
          # these are run from each shard (not needed, but simplifies the implementation).
          #
          # Do not reload the migration when running inline, because it can be from a different shard
          # than the "default" shard (which is used to lookup background migrations).
          if !Utils.run_background_migrations_inline?
            # Reload to check if the migration's status changed etc.
            @migration.reload
          end
        end

        @throttle_checked_at = current_time
      end

      def on_start
        @migration.start
      end

      def on_resume
        @data_migration.after_resume
      end

      def on_stop
        @ticker.persist
        @migration.stop
      end

      def on_complete
        # Job was manually cancelled.
        @migration.cancel if cancelled?

        @migration.complete
      end

      def build_enumerator(migration_id, cursor:)
        @migration = BackgroundDataMigrations::Migration.find(migration_id)
        cursor ||= @migration.cursor

        @migration.on_shard_if_present do
          @data_migration = @migration.data_migration
          collection_enum = @data_migration.build_enumerator(cursor: cursor)

          if collection_enum
            if !collection_enum.is_a?(Enumerator)
              raise ArgumentError, <<~MSG.squish
                #{@data_migration.class.name}#build_enumerator must return an Enumerator,
                got #{collection_enum.class.name}.
              MSG
            end

            collection_enum
          else
            collection = @data_migration.collection

            case collection
            when ActiveRecord::Relation
              options = {
                cursor: cursor,
                batch_size: @data_migration.class.active_record_enumerator_batch_size || 100,
              }
              active_record_records_enumerator(collection, **options)
            when ActiveRecord::Batches::BatchEnumerator
              if collection.start || collection.finish
                raise ArgumentError, <<~MSG.squish
                  #{@data_migration.class.name}#collection does not support
                  a batch enumerator with the "start" or "finish" options.
                MSG
              end

              active_record_relations_enumerator(
                collection.relation,
                batch_size: collection.batch_size,
                cursor: cursor,
                use_ranges: collection.use_ranges
              )
            when Array
              array_enumerator(collection, cursor: cursor)
            else
              raise ArgumentError, <<~MSG.squish
                #{@data_migration.class.name}#collection must be either an ActiveRecord::Relation,
                ActiveRecord::Batches::BatchEnumerator, or Array.
              MSG
            end
          end
        end
      end

      def each_iteration(item, _migration_id)
        if @migration.cancelling? || @migration.pausing? || @migration.paused?
          # Finish this exact sidekiq job. When the migration is paused
          # and will be resumed, a new job will be enqueued.
          finished = true
          throw :abort, finished
        elsif should_throttle?
          ActiveSupport::Notifications.instrument("throttled.background_data_migrations", migration: @migration)
          finished = false
          throw :abort, finished
        else
          @data_migration.around_process do
            @migration.data_migration.process(item)

            # Migration is refreshed regularly by ticker.
            pause = @migration.iteration_pause
            sleep(pause) if pause > 0
          end
          @ticker.tick
        end
      end

      private
        # It would be better for sidekiq to have a callback like `around_perform`,
        # but currently this is the way to make job iteration shard aware.
        def iterate_with_enumerator(enumerator, arguments)
          @migration.on_shard_if_present { super }
        end

        THROTTLE_CHECK_INTERVAL = 5 # seconds
        private_constant :THROTTLE_CHECK_INTERVAL

        def should_throttle?
          if current_time - @throttle_checked_at >= THROTTLE_CHECK_INTERVAL
            @throttle_checked_at = current_time
            OnlineMigrations.config.throttler.call
          end
        end

        def current_time
          ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
        end
    end
  end
end
