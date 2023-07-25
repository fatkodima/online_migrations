# frozen_string_literal: true

require "test_helper"

class CommandRecorderTest < MiniTest::Test
  def setup
    @connection = ActiveRecord::Base.connection
    @connection.create_table(:users) do |t|
      t.text :name
    end
  end

  def teardown
    @connection.execute("DROP VIEW users CASCADE") rescue nil
    @connection.drop_table(:users) rescue nil
  end

  class UpdateColumnInBatches < TestMigration
    disable_ddl_transaction!

    def change
      update_column_in_batches(:users, :name, "Guest")
    end
  end

  def test_update_column_in_batches
    assert_irreversible do
      migrate(UpdateColumnInBatches, direction: :down)
    end
  end

  class RenameColumnConcurrently < TestMigration
    def change
      initialize_column_rename(:users, :name, :first_name)
    end
  end

  def test_initialize_column_rename
    migrate(RenameColumnConcurrently, direction: :up)
    assert @connection.column_exists?(:users, :first_name)

    migrate(RenameColumnConcurrently, direction: :down)
    assert_not @connection.column_exists?(:users, :first_name)
  end

  class UndoRenameColumnConcurrently < TestMigration
    def change
      revert_initialize_column_rename(:users, :name, :first_name)
    end
  end

  def test_revert_initialize_column_rename
    @connection.initialize_column_rename(:users, :name, :first_name)

    migrate(UndoRenameColumnConcurrently, direction: :up)
    assert_not @connection.column_exists?(:users, :first_name)

    migrate(UndoRenameColumnConcurrently, direction: :down)
    assert @connection.column_exists?(:users, :first_name)
  ensure
    @connection.revert_initialize_column_rename(:users, :name, :first_name)
  end

  class CleanupRenameColumnConcurrently < TestMigration
    def change
      finalize_column_rename(:users, :name, :first_name)
    end
  end

  def test_finalize_column_rename
    @connection.initialize_column_rename(:users, :name, :first_name)

    migrate(CleanupRenameColumnConcurrently, direction: :up)
    assert_not @connection.column_exists?(:users, :name)

    migrate(CleanupRenameColumnConcurrently, direction: :down)
    assert @connection.column_exists?(:users, :name)
  ensure
    @connection.revert_initialize_column_rename(:users, :name, :first_name)
  end

  class UndoCleanupRenameColumnConcurrently < TestMigration
    def change
      revert_finalize_column_rename(:users, :name, :first_name)
    end
  end

  def test_revert_finalize_column_rename
    @connection.initialize_column_rename(:users, :name, :first_name)
    @connection.finalize_column_rename(:users, :name, :first_name)

    migrate(UndoCleanupRenameColumnConcurrently, direction: :up)
    assert @connection.column_exists?(:users, :name)

    migrate(UndoCleanupRenameColumnConcurrently, direction: :down)
    assert_not @connection.column_exists?(:users, :name)
  end

  class RenameTableConcurrently < TestMigration
    def change
      initialize_table_rename(:users, :clients)
    end
  end

  def test_initialize_table_rename
    migrate(RenameTableConcurrently, direction: :up)
    assert @connection.table_exists?(:clients)

    migrate(RenameTableConcurrently, direction: :down)
    assert_not @connection.table_exists?(:clients)
  end

  class CleanupRenameTableConcurrently < TestMigration
    def change
      finalize_table_rename(:users, :clients)
    end
  end

  def test_finalize_table_rename
    @connection.initialize_table_rename(:users, :clients)

    migrate(CleanupRenameTableConcurrently, direction: :up)
    refute_includes @connection.views, "users"

    migrate(CleanupRenameTableConcurrently, direction: :down)
    assert_includes @connection.views, "users"
  ensure
    @connection.revert_initialize_table_rename(:users, :clients)
  end

  class InitializeColumnTypeChange < TestMigration
    def change
      initialize_column_type_change(:users, :name, :string)
    end
  end

  def test_initialize_column_type_change
    migrate(InitializeColumnTypeChange, direction: :up)
    assert @connection.column_exists?(:users, :name_for_type_change)

    migrate(InitializeColumnTypeChange, direction: :down)
    assert_not @connection.column_exists?(:users, :name_for_type_change)
  end

  class CopyColumnForTypeChange < TestMigration
    disable_ddl_transaction!

    def change
      backfill_column_for_type_change(:users, :name)
    end
  end

  def test_backfill_column_for_type_change
    @connection.initialize_column_type_change(:users, :name, :string)

    assert_irreversible do
      migrate(CopyColumnForTypeChange, direction: :down)
    end
  end

  class SwapColumnNames < TestMigration
    def change
      swap_column_names :users, :name, :name_for_type_change
    end
  end

  def test_swap_column_names
    @connection.add_column(:users, :name_for_type_change, :string)

    migrate(SwapColumnNames, direction: :up)
    assert_equal :string, column_for(:users, :name).type

    migrate(SwapColumnNames, direction: :down)
    assert_equal :text, column_for(:users, :name).type
  end

  class AddColumnWithDefault < TestMigration
    disable_ddl_transaction!

    def change
      add_column_with_default :users, :admin, :boolean, default: false
    end
  end

  def test_add_column_with_default
    migrate(AddColumnWithDefault, direction: :up)
    assert @connection.column_exists?(:users, :admin)

    migrate(AddColumnWithDefault, direction: :down)
    assert_not @connection.column_exists?(:users, :admin)
  end

  class AddNotNullConstraint < TestMigration
    def change
      add_not_null_constraint :users, :name, name: "name_not_null", validate: false
    end
  end

  def test_add_not_null_constraint
    migrate(AddNotNullConstraint, direction: :up)
    assert @connection.send(:__not_null_constraint_exists?, :users, :name, name: "name_not_null")

    migrate(AddNotNullConstraint, direction: :down)
    assert_not @connection.send(:__not_null_constraint_exists?, :users, :name, name: "name_not_null")
  end

  class RemoveNotNullConstraint < TestMigration
    def change
      remove_not_null_constraint :users, :name
    end
  end

  def test_remove_not_null_constraint
    @connection.add_not_null_constraint :users, :name

    migrate(RemoveNotNullConstraint, direction: :up)
    assert_not @connection.send(:__not_null_constraint_exists?, :users, :name)

    migrate(RemoveNotNullConstraint, direction: :down)
    assert @connection.send(:__not_null_constraint_exists?, :users, :name)
  end

  class AddTextLimitConstraint < TestMigration
    def change
      add_text_limit_constraint :users, :name, 255, name: "name_limit", validate: false
    end
  end

  def test_add_text_limit_constraint
    migrate(AddTextLimitConstraint, direction: :up)
    assert @connection.send(:__text_limit_constraint_exists?, :users, :name, name: "name_limit")

    migrate(AddTextLimitConstraint, direction: :down)
    assert_not @connection.send(:__text_limit_constraint_exists?, :users, :name, name: "name_limit")
  end

  class RemoveTextLimitConstraint < TestMigration
    def change
      remove_text_limit_constraint :users, :name, 255, name: "name_limit"
    end
  end

  def test_remove_text_limit_constraint
    @connection.add_text_limit_constraint :users, :name, 255, name: "name_limit"

    migrate(RemoveTextLimitConstraint, direction: :up)
    assert_not @connection.send(:__text_limit_constraint_exists?, :users, :name, name: "name_limit")

    migrate(RemoveTextLimitConstraint, direction: :down)
    assert @connection.send(:__text_limit_constraint_exists?, :users, :name, name: "name_limit")
  end

  private
    def assert_irreversible(&block)
      error = assert_raises(&block)
      assert_instance_of ActiveRecord::IrreversibleMigration, error.cause
    end

    def column_for(table_name, column_name)
      @connection.columns(table_name).find { |c| c.name == column_name.to_s }
    end
end
