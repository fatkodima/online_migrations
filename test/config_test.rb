# frozen_string_literal: true

require "test_helper"

class ConfigTest < MiniTest::Test
  def setup
    connection = ActiveRecord::Base.connection

    connection.create_table(:users, force: :cascade) do |t|
      t.string :name
    end
  end

  def teardown
    connection = ActiveRecord::Base.connection
    connection.drop_table(:users) rescue nil
  end

  class RemoveNameFromUsers < TestMigration
    def change
      remove_column :users, :name, :string
    end

    def version
      20200101000001
    end
  end

  def test_configurable_error_messages
    error_messages = OnlineMigrations.config.error_messages
    prev = error_messages[:remove_column]

    error_messages[:remove_column] = "Your custom instructions"
    assert_unsafe RemoveNameFromUsers, "Your custom instructions"
  ensure
    error_messages[:remove_column] = prev
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

  def test_start_after_multiple_dbs_below_6
    skip if supports_multiple_dbs?

    assert_raises(RuntimeError, "Multiple databases are not supported by this ActiveRecord version") do
      config.start_after = { primary: 20200101000001 }
    end
  end

  def test_start_after_multiple_dbs
    skip unless supports_multiple_dbs?

    with_multiple_dbs do
      with_start_after({ primary: 20200101000001 }) do
        assert_safe RemoveNameFromUsers
      end

      with_start_after({ primary: 20200101000000 }) do
        assert_unsafe RemoveNameFromUsers
      end
    end
  end

  def test_start_after_multiple_dbs_unconfigured
    skip unless supports_multiple_dbs?

    with_multiple_dbs(connects_to: :primary) do
      assert_raises(StandardError, /OnlineMigrations.config.start_after is not configured for :primary/i) do
        with_start_after({ animals: 20200101000001 }) do
          assert_safe RemoveNameFromUsers
        end
      end
    end
  end

  class AddColumnDefault < TestMigration
    def change
      add_column :users, :admin, :boolean, default: false
    end
  end

  def test_target_version_safe
    with_target_version(11) do
      assert_safe AddColumnDefault
    end
  end

  def test_target_version_unsafe
    with_target_version(10) do
      assert_unsafe AddColumnDefault
    end
  end

  def test_target_version_multiple_dbs_below_6
    skip if supports_multiple_dbs?

    assert_raises(RuntimeError, "Multiple databases are not supported by this ActiveRecord version") do
      config.target_version = { primary: 10 }
    end
  end

  def test_target_version_multiple_dbs
    skip unless supports_multiple_dbs?

    with_multiple_dbs do
      with_target_version({ primary: 11 }) do
        assert_safe AddColumnDefault
      end

      with_target_version({ primary: 10 }) do
        assert_unsafe AddColumnDefault
      end
    end
  end

  def test_target_version_multiple_dbs_unconfigured
    skip unless supports_multiple_dbs?

    with_multiple_dbs(connects_to: :primary) do
      assert_raises(StandardError, /OnlineMigrations.config.with_target_version is not configured for :primary/i) do
        with_target_version({ animals: 10 }) do
          assert_safe AddColumnDefault
        end
      end
    end
  end

  def test_background_migrations_throttler
    previous = config.background_migrations.throttler

    error = assert_raises(ArgumentError) do
      config.background_migrations.throttler = :not_callable
    end
    assert_equal "background_migrations throttler must be a callable.", error.message

    config.background_migrations.throttler = -> { :callable }
  ensure
    config.background_migrations.throttler = previous
  end

  def test_disable_check
    config.disable_check(:remove_column)
    assert_safe RemoveNameFromUsers
  ensure
    config.enable_check(:remove_column)
  end

  def test_enable_check
    config.disable_check(:remove_column)
    config.enable_check(:remove_column)
    assert_unsafe RemoveNameFromUsers
  ensure
    config.enable_check(:remove_column)
  end

  def test_enable_check_start_after
    config.enable_check(:remove_column, start_after: 20200101000002)
    assert_safe RemoveNameFromUsers
  ensure
    config.enable_check(:remove_column)
  end

  class AddIndexToUsers < TestMigration
    def change
      add_index :users, :name
    end
  end

  def test_small_tables
    config.small_tables = [:users]

    assert_safe AddIndexToUsers
  ensure
    config.small_tables.clear
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
    def with_multiple_dbs(connects_to: :primary, &block)
      database_yml = File.expand_path("support/multiple_database.yml", __dir__)
      yaml = File.read(database_yml)

      prev_configs = ActiveRecord::Base.configurations
      ActiveRecord::Base.configurations =
        YAML.respond_to?(:unsafe_load) ? YAML.unsafe_load(yaml) : YAML.load(yaml) # rubocop:disable Security/YAMLLoad

      ActiveRecord::Base.connects_to(database: { writing: connects_to })

      ActiveRecord::Base.connected_to(role: :writing, &block)
    ensure
      ActiveRecord::Base.configurations = prev_configs
      ActiveRecord::Base.establish_connection(:postgresql)
    end

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
