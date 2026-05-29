# frozen_string_literal: true

require "test_helper"
require_relative "background_data_migrations/data_migrations"

class DataMigrationTest < Minitest::Test
  def test_named_returns_migration_based_on_name
    expected_migration = BackgroundDataMigrations::MakeAllNonAdmins
    assert_equal expected_migration, OnlineMigrations::DataMigration.named("MakeAllNonAdmins")
  end

  def test_named_raises_for_nonexistent_migration
    error = assert_raises(OnlineMigrations::DataMigration::NotFoundError) do
      OnlineMigrations::DataMigration.named("DoesNotExist")
    end
    assert_includes error.message, "Data Migration DoesNotExist not found"
    assert_equal "DoesNotExist", error.name
  end

  def test_named_raises_if_name_does_not_refer_to_migration
    assert_raises_with_message(ArgumentError, /NotAMigration is not a Data Migration/i) do
      OnlineMigrations::DataMigration.named("NotAMigration")
    end
  end
end
