# frozen_string_literal: true

require "test_helper"

class LockRetrierTest < MiniTest::Test
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
    @connection.execute("SET lock_timeout TO '1ms'")

    @connection.create_table(:users)
    $migrate_attempts = 0
  end

  def teardown
    @connection.drop_table(:users) rescue nil
  end

  def test_with_retries
    with_table_locked(:users) do
      with_lock_retries do
        assert_lock_timeout { migrate(LockRetriesMigration) }
      end
    end
    # 3 = first run + 2 attempts
    assert_equal 3, $migrate_attempts
  end

  def test_with_retries_no_transaction
    with_table_locked(:users) do
      with_lock_retries do
        assert_lock_timeout { migrate(LockRetriesNoTransactionMigration) }
      end
    end

    # Initial run only, then just `add_column` is retried
    assert_equal 1, $migrate_attempts
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
