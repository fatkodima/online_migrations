# frozen_string_literal: true

require "test_helper"

class LockRetrierTest < Minitest::Test
  class LockRetriesMigration < TestMigration
    def change
      $migrate_attempts += 1
      add_column :users, :name, :string
    end
  end

  class LockRetriesNoTransactionMigration < TestMigration
    disable_ddl_transaction!

    def change
      $migrate_attempts += 1
      add_column :users, :name, :string
    end
  end

  def setup
    @connection = ActiveRecord::Base.connection
    @connection.create_table(:users)
    $migrate_attempts = 0
    $lock_timeout_calls = []
  end

  def teardown
    @connection.drop_table(:users, if_exists: true)
  end

  def test_with_retries
    with_table_locked(:users) do
      with_lock_retries do
        assert_lock_timeout { migrate(LockRetriesMigration) }
      end
    end
    # 3 = first run + 2 attempts (entire migration is retried)
    assert_equal 3, $migrate_attempts
  end

  def test_with_retries_no_transaction
    with_table_locked(:users) do
      with_lock_retries do
        assert_lock_timeout { migrate(LockRetriesNoTransactionMigration) }
      end
    end

    # Initial run only, then just `add_column` is retried (not the whole migration)
    assert_equal 1, $migrate_attempts
  end

  class CommandAwareLockRetrier < OnlineMigrations::LockRetrier
    def attempts(_command = nil, _arguments = [])
      2
    end

    def lock_timeout(attempt, command = nil, arguments = [])
      $lock_timeout_calls << { attempt: attempt, command: command, arguments: arguments }
      0.001.seconds
    end

    def delay(_attempt, _command = nil, _arguments = [])
      0
    end
  end

  def test_command_aware_lock_retrier
    previous = OnlineMigrations.config.lock_retrier
    OnlineMigrations.config.lock_retrier = CommandAwareLockRetrier.new

    with_table_locked(:users) do
      assert_lock_timeout { migrate(LockRetriesNoTransactionMigration) }
    end

    # Verify command and arguments were passed to lock_timeout
    # With attempts=2, it will try: attempt 1, 2, and 3 (initial + 2 retries)
    assert_equal 3, $lock_timeout_calls.size

    # Verify all calls have the correct command and arguments
    $lock_timeout_calls.each_with_index do |call, index|
      assert_equal index + 1, call[:attempt]
      assert_equal :add_column, call[:command]
      assert_equal [:users, :name, :string], call[:arguments]
    end
  ensure
    OnlineMigrations.config.lock_retrier = previous
  end

  class AddIndexConcurrentlyMigration < TestMigration
    disable_ddl_transaction!

    def change
      add_index :users, :name, algorithm: :concurrently
    end
  end

  class RemoveIndexConcurrentlyMigration < TestMigration
    disable_ddl_transaction!

    def change
      remove_index :users, :name, algorithm: :concurrently
    end
  end

  class AddReferenceConcurrentlyMigration < TestMigration
    disable_ddl_transaction!

    def change
      add_reference_concurrently :users, :project
    end
  end

  class AddReferenceMigration < TestMigration
    disable_ddl_transaction!

    def change
      add_reference :users, :project, index: { algorithm: :concurrently }
    end
  end

  def test_concurrent_lock_timeout
    @connection.add_column(:users, :name, :string)

    statements = with_concurrent_lock_retrier do
      lock_statements { migrate(AddIndexConcurrentlyMigration) }
    end

    assert_equal ["SET lock_timeout TO '5000ms'", "SET lock_timeout TO '180000ms'",
                  "CREATE INDEX CONCURRENTLY", "SET lock_timeout TO '5s'",
                  "SET lock_timeout TO '5ms'"], statements
  end

  def test_concurrent_lock_timeout_when_removing_an_index
    @connection.add_column(:users, :name, :string)
    @connection.add_index(:users, :name)

    statements = with_concurrent_lock_retrier do
      lock_statements { migrate(RemoveIndexConcurrentlyMigration) }
    end

    assert_equal ["SET lock_timeout TO '5000ms'", "SET lock_timeout TO '180000ms'",
                  "DROP INDEX CONCURRENTLY", "SET lock_timeout TO '5s'",
                  "SET lock_timeout TO '5ms'"], statements
  end

  # `add_reference_concurrently` issues an "ACCESS EXCLUSIVE" ADD COLUMN and a
  # concurrent index build under one command, so only the index statement may
  # get the longer timeout.
  def test_concurrent_lock_timeout_is_not_applied_to_other_statements_in_the_same_command
    statements = with_concurrent_lock_retrier do
      lock_statements { migrate(AddReferenceConcurrentlyMigration) }
    end

    assert_equal ["SET lock_timeout TO '5000ms'", "ALTER TABLE", "SET lock_timeout TO '180000ms'",
                  "CREATE INDEX CONCURRENTLY", "SET lock_timeout TO '5s'",
                  "SET lock_timeout TO '5ms'"], statements
  end

  def test_concurrent_lock_timeout_with_plain_add_reference
    statements = with_concurrent_lock_retrier do
      lock_statements { migrate(AddReferenceMigration) }
    end

    assert_equal ["SET lock_timeout TO '5000ms'", "ALTER TABLE", "SET lock_timeout TO '180000ms'",
                  "CREATE INDEX CONCURRENTLY", "SET lock_timeout TO '5s'",
                  "SET lock_timeout TO '5ms'"], statements
  end

  def test_concurrent_lock_timeout_is_not_set_by_default
    @connection.add_column(:users, :name, :string)

    previous = OnlineMigrations.config.lock_retrier
    OnlineMigrations.config.lock_retrier =
      OnlineMigrations::ConstantLockRetrier.new(attempts: 1, delay: 0, lock_timeout: 5.seconds)

    statements = lock_statements { migrate(AddIndexConcurrentlyMigration) }

    assert_equal ["SET lock_timeout TO '5000ms'", "CREATE INDEX CONCURRENTLY",
                  "SET lock_timeout TO '5ms'"], statements
  ensure
    OnlineMigrations.config.lock_retrier = previous
  end

  def test_null_lock_retrier
    previous = OnlineMigrations.config.lock_retrier

    # Setting config.lock_retrier to +OnlineMigrations::NullLockRetrier+
    OnlineMigrations.config.lock_retrier = nil

    with_table_locked(:users) do
      assert_lock_timeout { migrate(LockRetriesMigration) }
    end

    # Does not retry migration
    assert_equal 1, $migrate_attempts
  ensure
    OnlineMigrations.config.lock_retrier = previous
  end

  private
    def with_table_locked(table_name)
      connection = ActiveRecord::Base.connection_pool.checkout

      connection.transaction do
        connection.execute("LOCK TABLE #{table_name} IN ACCESS EXCLUSIVE MODE")
        yield
      end
    ensure
      ActiveRecord::Base.connection_pool.checkin(connection) if connection
    end

    def with_lock_retries
      previous = OnlineMigrations.config.lock_retrier
      OnlineMigrations.config.lock_retrier = OnlineMigrations::ConstantLockRetrier.new(attempts: 2, delay: 0, lock_timeout: 0.001)

      yield
    ensure
      OnlineMigrations.config.lock_retrier = previous
    end

    def with_concurrent_lock_retrier
      previous = OnlineMigrations.config.lock_retrier
      OnlineMigrations.config.lock_retrier = OnlineMigrations::ConstantLockRetrier.new(
        attempts: 1, delay: 0, lock_timeout: 5.seconds, concurrent_lock_timeout: 3.minutes
      )

      yield
    ensure
      OnlineMigrations.config.lock_retrier = previous
    end

    # The lock timeout changes and the DDL they are meant to cover, in the order
    # PostgreSQL received them.
    def lock_statements(&block)
      track_queries(&block).filter_map do |sql|
        case sql
        when /\ASET lock_timeout/ then sql
        when /\ACREATE INDEX CONCURRENTLY/ then "CREATE INDEX CONCURRENTLY"
        when /\ADROP INDEX CONCURRENTLY/ then "DROP INDEX CONCURRENTLY"
        when /\AALTER TABLE/ then "ALTER TABLE"
        end
      end
    end

    def assert_lock_timeout(&block)
      error = assert_raises(&block)
      assert_match(/canceling statement due to lock timeout/, error.message)
    end
end
