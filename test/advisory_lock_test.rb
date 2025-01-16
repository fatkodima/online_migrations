# frozen_string_literal: true

require "test_helper"

class AdvisoryLockTest < Minitest::Test
  def setup
    @lock = OnlineMigrations::AdvisoryLock.new(name: "somename")
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

  def test_try_with_lock
    assert_not @lock.active?

    called = false
    @lock.try_with_lock do
      called = true
      assert @lock.active?
    end
    assert called

    assert_not @lock.active?
  end
end
