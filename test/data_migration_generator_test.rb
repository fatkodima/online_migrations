# frozen_string_literal: true

require "test_helper"

require "generators/online_migrations/data_migration_generator"

class DataMigrationGeneratorTest < Rails::Generators::TestCase
  tests OnlineMigrations::DataMigrationGenerator
  destination File.expand_path("../tmp", __dir__)
  setup :prepare_destination

  def test_creates_data_migration_file
    run_generator(["make_all_non_admins"])

    assert_file("lib/background_data_migrations/make_all_non_admins.rb") do |content|
      assert_includes content, "module BackgroundDataMigrations"
      assert_includes content, "class MakeAllNonAdmins < OnlineMigrations::DataMigration"
      assert_includes content, "def collection"
      assert_includes content, "def process(element)"
      assert_includes content, "def count"
    end
  end

  def test_creates_migration_file
    run_generator(["make_all_non_admins"])

    assert_migration("db/migrate/enqueue_make_all_non_admins.rb") do |content|
      assert_includes content, "class EnqueueMakeAllNonAdmins < ActiveRecord::Migration"
      assert_includes content, 'enqueue_background_data_migration("MakeAllNonAdmins"'
      assert_includes content, 'remove_background_data_migration("MakeAllNonAdmins"'
    end
  end

  def test_generator_uses_configured_migrations_path
    OnlineMigrations.config.background_data_migrations.stub(:migrations_path, "app/lib") do
      run_generator(["make_all_non_admins"])

      assert_file("app/lib/background_data_migrations/make_all_non_admins.rb") do |content|
        assert_includes content, "module BackgroundDataMigrations"
      end
    end
  end

  def test_generator_uses_configured_migrations_module
    OnlineMigrations.config.background_data_migrations.stub(:migrations_module, "Foo") do
      run_generator(["make_all_non_admins"])

      assert_file("lib/foo/make_all_non_admins.rb") do |content|
        assert_includes content, "module Foo"
      end
    end
  end

  def test_generator_namespaces_properly
    run_generator(["users/make_all_non_admins"])

    assert_file("lib/background_data_migrations/users/make_all_non_admins.rb") do |content|
      assert_includes content, "class Users::MakeAllNonAdmins < OnlineMigrations::DataMigration"
    end
  end
end
