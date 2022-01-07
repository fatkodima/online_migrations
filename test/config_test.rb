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
