# frozen_string_literal: true

require "test_helper"

require "generators/online_migrations/install_generator"

class InstallGeneratorTest < Rails::Generators::TestCase
  tests OnlineMigrations::InstallGenerator
  destination File.expand_path("../tmp", __dir__)
  setup :prepare_destination

  def test_creates_migration_file
    run_generator

    assert_migration("db/migrate/install_online_migrations.rb") do |content|
      assert_includes content, "create_table :background_migrations"
      assert_includes content, "create_table :background_migration_jobs"
    end
  end

  def test_creates_initializer_file
    run_generator

    assert_file("config/initializers/online_migrations.rb") do |content|
      assert_includes content, "OnlineMigrations.configure do |config|"
    end
  end
end
