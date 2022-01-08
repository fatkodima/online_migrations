# frozen_string_literal: true

require "test_helper"
require_relative "background_migrations/migrations"

class BackgroundMigrationTest < MiniTest::Test
  def test_named_returns_migration_based_on_name
    expected_migration = BackgroundMigrations::MakeAllNonAdmins
    assert_equal expected_migration, OnlineMigrations::BackgroundMigration.named("MakeAllNonAdmins")
  end

  def test_named_raises_for_nonexistent_migration
    error = assert_raises(OnlineMigrations::BackgroundMigration::NotFoundError) do
      OnlineMigrations::BackgroundMigration.named("DoesNotExist")
    end
    assert_equal "Background Migration DoesNotExist not found", error.message
    assert_equal "DoesNotExist", error.name
  end

  def test_named_raises_if_name_does_not_refer_to_migration
    error = assert_raises(OnlineMigrations::BackgroundMigration::NotFoundError) do
      OnlineMigrations::BackgroundMigration.named("NotAMigration")
    end
    assert_equal "NotAMigration is not a Background Migration", error.message
    assert_equal "NotAMigration", error.name
  end
end
