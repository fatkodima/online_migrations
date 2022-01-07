# frozen_string_literal: true

require "test_helper"

class ConfigTest < MiniTest::Test
  def setup
    @connection = ActiveRecord::Base.connection

    @connection.create_table(:users, force: :cascade) do |t|
      t.string :name
    end
  end

  def teardown
    @connection.drop_table(:users) rescue nil
  end

  class RemoveNameFromUsers < TestMigration
    def change
      remove_column :users, :name, :string
    end

    def version
      20200101000001
    end
  end

  def test_start_after_safe
    with_start_after(20200101000001) do
      assert_safe RemoveNameFromUsers
    end
  end

  def test_start_after_unsafe
    with_start_after(20200101000000) do
      assert_unsafe RemoveNameFromUsers
    end
  end

  class CheckDownMigration < TestMigration
    disable_ddl_transaction!

    def up
      add_index :users, :name, algorithm: :concurrently
    end

    def down
      remove_index :users, :name
    end
  end

  def test_check_down
    migrate CheckDownMigration
    assert_safe CheckDownMigration, direction: :down

    migrate CheckDownMigration
    with_check_down do
      assert_unsafe CheckDownMigration, direction: :down
    end
    migrate CheckDownMigration, direction: :down
  end

  private
    def with_start_after(value)
      previous = config.start_after
      config.start_after = value

      yield
    ensure
      config.start_after = previous
    end

    def with_check_down
      previous = config.check_down
      config.check_down = true

      yield
    ensure
      config.check_down = previous
    end

    def config
      OnlineMigrations.config
    end
end
