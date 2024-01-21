# frozen_string_literal: true

require "test_helper"

require "generators/online_migrations/background_migration_generator"

class BackgroundMigrationGeneratorTest < Rails::Generators::TestCase
  tests OnlineMigrations::BackgroundMigrationGenerator
  destination File.expand_path("../tmp", __dir__)
  setup :prepare_destination

  def test_creates_background_migration_file
    run_generator(["make_all_non_admins"])

    assert_file("lib/background_migrations/make_all_non_admins.rb") do |content|
      assert_includes content, "module BackgroundMigrations"
      assert_includes content, "class MakeAllNonAdmins < OnlineMigrations::BackgroundMigration"
      assert_includes content, "def relation"
      assert_includes content, "def process_batch(relation)"
      assert_includes content, "def count"
    end
  end

  def test_generator_uses_configured_migrations_path
    OnlineMigrations.config.background_migrations.stub(:migrations_path, "app/lib") do
      run_generator(["make_all_non_admins"])

      assert_file("app/lib/background_migrations/make_all_non_admins.rb") do |content|
        assert_includes content, "module BackgroundMigrations"
      end
    end
  end

  def test_generator_uses_configured_migrations_module
    OnlineMigrations.config.background_migrations.stub(:migrations_module, "Foo") do
      run_generator(["make_all_non_admins"])

      assert_file("lib/foo/make_all_non_admins.rb") do |content|
        assert_includes content, "module Foo"
      end
    end
  end

  def test_generator_namespaces_properly
    run_generator(["users/make_all_non_admins"])

    assert_file("lib/background_migrations/users/make_all_non_admins.rb") do |content|
      assert_includes content, "class Users::MakeAllNonAdmins < OnlineMigrations::BackgroundMigration"
    end
  end
end
