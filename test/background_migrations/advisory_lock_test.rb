# frozen_string_literal: true

require "test_helper"

module BackgroundMigrations
  class AdvisoryLockTest < Minitest::Test
    def setup
      @lock = OnlineMigrations::BackgroundMigrations::AdvisoryLock.new(name: "somename")
    end

    def teardown
      @lock.unlock if @lock.active?
    end

    def test_try_lock
      locked = @lock.try_lock
      assert locked
      assert @lock.active?
    end

    def test_unlock
      @lock.try_lock
      assert @lock.active?
      @lock.unlock
      assert_not @lock.active?
    end

    def test_with_lock
      assert_not @lock.active?

      @lock.with_lock do
        assert @lock.active?
      end

      assert_not @lock.active?
    end
  end
end
