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
  end

  def teardown
    @connection.drop_table(:users, if_exists: true)
  end

  def test_with_retries
    with_table_locked(:users) do
      with_lock_retries do
        # this doesn't pass the command to the lock_retrier.lock_timeout method - why?
        assert_lock_timeout { migrate(LockRetriesMigration) }
      end
    end
    # 3 = first run + 2 attempts
    assert_equal 3, $migrate_attempts
  end

  def test_with_retries_no_transaction
    with_table_locked(:users) do
      with_lock_retries do
        # this does pass the command to the lock_retrier.lock_timeout method
        assert_lock_timeout { migrate(LockRetriesNoTransactionMigration) }
      end
    end

    # Initial run only, then just `add_column` is retried
    assert_equal 1, $migrate_attempts
  end

  def test_lock_timeout_accepts_command_parameter
    retrier = OnlineMigrations::ConstantLockRetrier.new(
      attempts: 1,
      delay: 0,
      lock_timeout: 0.001
    )

    # Verify the method accepts both attempt and command parameters
    assert_nothing_raised do
      retrier.lock_timeout(1, command: "ALTER TABLE", arguments: ["users"])
    end

    # Verify it returns the expected lock_timeout value
    assert_in_delta(0.001, retrier.lock_timeout(1, command: "ALTER TABLE", arguments: ["users"]))
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
