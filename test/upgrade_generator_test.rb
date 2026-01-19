# frozen_string_literal: true

require "test_helper"

require "generators/online_migrations/upgrade_generator"

class UpgradeGeneratorTest < Rails::Generators::TestCase
  tests OnlineMigrations::UpgradeGenerator
  destination File.expand_path("../tmp", __dir__)
  setup :prepare_destination

  def test_adds_sharding_to_background_migrations
    simulate_transactional_test do
      load_schema(1)
      run_generator

      assert_migration("db/migrate/add_sharding_to_online_migrations.rb") do |content|
        assert_includes content, "change_table :background_migrations"
        assert_includes content, "t.string :shard"
      end
    end
  end

  def test_adds_background_schema_migrations
    simulate_transactional_test do
      load_schema(2)
      run_generator

      assert_migration("db/migrate/create_background_schema_migrations.rb") do |content|
        assert_includes content, "create_table :background_schema_migrations"
      end
    end
  end

  def test_changes_background_schema_migrations_unique_index
    simulate_transactional_test do
      load_schema(2)
      run_generator

      assert_migration("db/migrate/background_schema_migrations_change_unique_index.rb") do |content|
        assert_includes content, "add_index :background_schema_migrations, [:migration_name, :table_name, :shard, :connection_class_name]"
      end
    end
  end

  def test_adds_timestamps_to_background_migrations
    simulate_transactional_test do
      load_schema(3)
      run_generator

      assert_migration("db/migrate/add_timestamps_to_background_migrations.rb") do |content|
        assert_includes content, "add_column :background_migrations, :started_at, :datetime"
        assert_includes content, "add_column :background_migrations, :finished_at, :datetime"
      end
    end
  end

  def test_adds_iteration_pause_to_background_data_migrations
    simulate_transactional_test do
      load_schema(4)
      run_generator

      assert_migration("db/migrate/background_data_migrations_add_iteration_pause.rb") do |content|
        assert_includes content, "add_column :background_data_migrations, :iteration_pause, :float"
      end
    end
  end

  def test_removes_iteration_pause_default_from_background_data_migrations
    simulate_transactional_test do
      load_schema(5)
      run_generator

      assert_migration("db/migrate/background_data_migrations_remove_iteration_pause_default.rb") do |content|
        assert_includes content, "change_column_default :background_data_migrations, :iteration_pause, nil"
      end
    end
  end

  def test_changes_status_default_for_background_data_migrations
    simulate_transactional_test do
      load_schema(6)
      run_generator

      assert_migration("db/migrate/background_migrations_change_status_default.rb") do |content|
        assert_includes content, 'change_column_default :background_data_migrations, :status, from: "enqueued", to: "pending"'
        assert_includes content, 'change_column_default :background_schema_migrations, :status, from: "enqueued", to: "pending"'
      end
    end
  end

  private
    def simulate_transactional_test
      ActiveRecord::Base.transaction do
        yield
        raise ActiveRecord::Rollback
      end
    end
end
