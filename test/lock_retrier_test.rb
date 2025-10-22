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

    def assert_lock_timeout(&block)
      error = assert_raises(&block)
      assert_match(/canceling statement due to lock timeout/, error.message)
    end
end
