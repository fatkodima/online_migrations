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

  private
    def simulate_transactional_test
      ActiveRecord::Base.transaction do
        yield
        raise ActiveRecord::Rollback
      end
    end
end
