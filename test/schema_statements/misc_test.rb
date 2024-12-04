# frozen_string_literal: true

require "test_helper"

module SchemaStatements
  class MiscTest < Minitest::Test
    class User < ActiveRecord::Base
      has_many :invoices
    end

    class Invoice < ActiveRecord::Base
      belongs_to :user, counter_cache: true
    end

    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users, force: :cascade) do |t|
        t.text :name
        t.string :status
        t.boolean :admin
        t.boolean :banned
        t.integer :invoices_count
        t.bigint :id_for_type_change
        t.string :name_for_type_change
      end

      @connection.create_table(:invoices, force: :cascade) do |t|
        t.belongs_to :user, foreign_key: false
        t.date :start_date
        t.date :end_date
      end

      User.reset_column_information
      Invoice.reset_column_information
    end

    def teardown
      OnlineMigrations::BackgroundMigrations::Migration.delete_all
      OnlineMigrations::BackgroundSchemaMigrations::Migration.delete_all
      @connection.drop_table(:invoices, if_exists: true)
      @connection.drop_table(:users, if_exists: true)
    end

    def test_schema
      if ActiveRecord.version >= Gem::Version.new("7.0.2")
        ActiveRecord::Schema[ar_version].define do
          add_index :users, :name
        end
      else
        ActiveRecord::Schema.define do
          add_index :users, :name
        end
      end
    end

    def test_add_exclusion_constraint
      skip if ar_version < 7.1

      user = User.create!
      start_date = 3.days.ago
      end_date = 1.day.ago

      user.invoices.create!(start_date: start_date, end_date: end_date)

      @connection.add_exclusion_constraint(:invoices, "daterange(start_date, end_date) WITH &&", using: :gist)

      error = assert_raises(ActiveRecord::StatementInvalid) do
        user.invoices.create!(start_date: start_date, end_date: end_date)
      end
      assert_instance_of PG::ExclusionViolation, error.cause
    end

    def test_add_exclusion_constraint_is_idempotent
      skip if ar_version < 7.1

      assert_nothing_raised do
        2.times do
          @connection.add_exclusion_constraint(:invoices, "daterange(start_date, end_date) WITH &&", using: :gist)
        end
      end
    end

    def test_swap_column_names
      @connection.swap_column_names(:users, :name, :name_for_type_change)

      assert_equal :string, column_for(:users, :name).type
      assert_equal :text, column_for(:users, :name_for_type_change).type
    end

    def test_backfill_column_in_background
      m = @connection.backfill_column_in_background(:users, :admin, false, model_name: User)

      assert_equal "BackfillColumn", m.migration_name
      assert_equal ["users", { "admin" => false }, "SchemaStatements::MiscTest::User"], m.arguments
    end

    def test_backfill_columns_in_background
      m = @connection.backfill_columns_in_background(:users, { admin: false, status: "active" }, model_name: User)

      assert_equal "BackfillColumn", m.migration_name
      assert_equal ["users", { "admin" => false, "status" => "active" }, "SchemaStatements::MiscTest::User"], m.arguments
    end

    def test_backfill_columns_in_background_raises_for_multiple_dbs_when_no_model_name
      error = assert_raises(ArgumentError) do
        @connection.backfill_columns_in_background(:users, { admin: false, status: "active" })
      end
      assert_match(/must pass a :model_name/i, error.message)
    end

    def test_copy_column_in_background
      m = @connection.copy_column_in_background(:users, :name, :name_for_type_change, model_name: User)

      assert_equal "CopyColumn", m.migration_name
      assert_equal ["users", ["name"], ["name_for_type_change"], "SchemaStatements::MiscTest::User", { "name" => nil }], m.arguments
    end

    def test_copy_columns_in_background
      m = @connection.copy_columns_in_background(:users, [:id, :name], [:id_for_type_change, :name_for_type_change], model_name: User)

      assert_equal "CopyColumn", m.migration_name
      assert_equal ["users", ["id", "name"], ["id_for_type_change", "name_for_type_change"], "SchemaStatements::MiscTest::User", {}], m.arguments
    end

    def test_copy_columns_in_background_raises_for_multiple_dbs_when_no_model_name
      error = assert_raises(ArgumentError) do
        @connection.copy_columns_in_background(:users, [:id, :name], [:id_for_type_change, :name_for_type_change])
      end
      assert_match(/must pass a :model_name/i, error.message)
    end

    def test_reset_counters_in_background
      m = @connection.reset_counters_in_background(User.name, :invoices, touch: true)

      assert_equal "ResetCounters", m.migration_name
      assert_equal [User.name, ["invoices"], { "touch" => true }], m.arguments
    end

    def test_delete_orphaned_records_in_background
      m = @connection.delete_orphaned_records_in_background(Invoice.name, :user)

      assert_equal "DeleteOrphanedRecords", m.migration_name
      assert_equal [Invoice.name, ["user"]], m.arguments
    end

    def test_delete_associated_records_in_background
      user = User.create!
      m = @connection.delete_associated_records_in_background(User.name, user.id, :invoices)

      assert_equal "DeleteAssociatedRecords", m.migration_name
      assert_equal [User.name, user.id, "invoices"], m.arguments
    end

    def test_perform_action_on_relation_in_background
      m = @connection.perform_action_on_relation_in_background(User.name, { banned: true }, :delete_all)

      assert_equal "PerformActionOnRelation", m.migration_name
      assert_equal [User.name, { "banned" => true }, "delete_all", { "updates" => nil }], m.arguments
    end

    def test_enqueue_background_data_migration
      assert_equal 0, OnlineMigrations::BackgroundMigrations::Migration.count
      m = @connection.enqueue_background_data_migration(
        "MakeAllNonAdmins",
        batch_max_attempts: 3,
        sub_batch_pause_ms: 200
      )

      assert_equal "MakeAllNonAdmins", m.migration_name
      assert_equal 3, m.batch_max_attempts
      assert_equal 200, m.sub_batch_pause_ms
      assert_equal OnlineMigrations.config.background_migrations.batch_size, m.batch_size
    end

    def test_enqueue_background_data_migration_is_idempotent
      assert_equal 0, OnlineMigrations::BackgroundMigrations::Migration.count
      2.times { @connection.enqueue_background_data_migration("MakeAllNonAdmins") }
      assert_equal 1, OnlineMigrations::BackgroundMigrations::Migration.count
    end

    def test_run_background_migrations_inline_true_in_local
      user = User.create!
      assert_nil user.admin

      m = @connection.enqueue_background_data_migration("MakeAllNonAdmins")
      assert m.succeeded?
      assert_equal false, user.reload.admin
    end

    def test_run_background_migrations_inline_configured_to_nil
      user = User.create!
      assert_nil user.admin

      m = OnlineMigrations.config.stub(:run_background_migrations_inline, nil) do
        @connection.enqueue_background_data_migration("MakeAllNonAdmins")
      end

      assert m.enqueued?
      assert_nil user.reload.admin
    end

    def test_run_background_migrations_inline_configured_to_custom_proc
      user = User.create!
      assert_nil user.admin

      prev = OnlineMigrations.config.run_background_migrations_inline
      OnlineMigrations.config.run_background_migrations_inline = -> { false }

      m = @connection.enqueue_background_data_migration("MakeAllNonAdmins")
      assert m.enqueued?
      assert_nil user.reload.admin
    ensure
      OnlineMigrations.config.run_background_migrations_inline = prev
    end

    def test_remove_non_existing_background_migration
      assert_nothing_raised do
        @connection.remove_background_data_migration("NonExistent")
      end
    end

    def test_remove_background_data_migration
      @connection.enqueue_background_data_migration("MakeAllNonAdmins")
      @connection.remove_background_data_migration("MakeAllNonAdmins")
      assert_equal 0, OnlineMigrations::BackgroundMigrations::Migration.count
    end

    def test_remove_background_data_migration_with_arguments
      @connection.enqueue_background_data_migration("MigrationWithArguments", 1, { "a" => 2 })
      @connection.remove_background_data_migration("MigrationWithArguments", 1, { "a" => 2 })
      assert_equal 0, OnlineMigrations::BackgroundMigrations::Migration.count
    end

    def test_ensure_background_data_migration_succeeded
      m = @connection.enqueue_background_data_migration("MakeAllNonAdmins")
      assert m.succeeded?
      assert_nothing_raised do
        @connection.ensure_background_data_migration_succeeded("MakeAllNonAdmins")
      end
    end

    def test_ensure_background_data_migration_succeeded_with_arguments
      m = @connection.enqueue_background_data_migration("MakeAllNonAdmins", 1, { foo: "bar" }, 2)
      assert m.succeeded?
      assert_nothing_raised do
        @connection.ensure_background_data_migration_succeeded("MakeAllNonAdmins", arguments: [1, { foo: "bar" }, 2])
      end
    end

    def test_ensure_background_data_migration_succeeded_when_migration_not_found
      out, = capture_io do
        logger = ActiveSupport::Logger.new($stdout)
        ActiveRecord::Base.stub(:logger, logger) do
          @connection.ensure_background_data_migration_succeeded("MakeAllNonAdmins")
        end
      end
      assert_match(/Could not find background data migration/i, out)
    end

    def test_ensure_background_data_migration_succeeded_when_migration_is_failed
      m = @connection.enqueue_background_data_migration("MakeAllNonAdmins")
      m.update_column(:status, :failed)

      assert_raises_with_message(RuntimeError, /to be marked as 'succeeded'/i) do
        @connection.ensure_background_data_migration_succeeded("MakeAllNonAdmins")
      end
    end

    def test_ensure_background_schema_migration_succeeded
      m = @connection.add_index_in_background(:users, :name, connection_class_name: "User")
      assert m.succeeded?
      assert_nothing_raised do
        @connection.ensure_background_schema_migration_succeeded(m.name)
      end
    end

    def test_ensure_background_schema_migration_succeeded_when_migration_not_found
      Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
        assert_raises_with_message(RuntimeError, /Could not find background schema migration/i) do
          @connection.ensure_background_schema_migration_succeeded("index_users_on_name")
        end
      end
    end

    def test_ensure_background_schema_migration_succeeded_when_migration_is_failed
      m = @connection.add_index_in_background(:users, :name, connection_class_name: "User")
      m.update_column(:status, :failed)

      assert_raises_with_message(RuntimeError, /to be marked as 'succeeded'/i) do
        @connection.ensure_background_schema_migration_succeeded("index_users_on_name")
      end
    end

    def test_validate_constraint_in_background
      @connection.add_foreign_key(:invoices, :users, name: "fk_invoices_user_id", validate: false)

      m = @connection.validate_constraint_in_background(:invoices, "fk_invoices_user_id", connection_class_name: "Invoice")
      assert_equal "fk_invoices_user_id", m.name
      assert_equal "invoices", m.table_name
      assert_equal 'ALTER TABLE "invoices" VALIDATE CONSTRAINT "fk_invoices_user_id"', m.definition
    end

    def test_disable_statement_timeout
      prev_value = get_statement_timeout
      set_statement_timeout(10)

      OnlineMigrations.deprecator.silence do
        @connection.disable_statement_timeout do
          assert_equal "0", get_statement_timeout
        end
      end
      assert_equal "10ms", get_statement_timeout
    ensure
      set_statement_timeout(prev_value)
    end

    def test_nested_disable_statement_timeouts
      prev_value = get_statement_timeout
      set_statement_timeout(10)

      OnlineMigrations.deprecator.silence do
        @connection.disable_statement_timeout do
          set_statement_timeout(20)

          @connection.disable_statement_timeout do
            assert_equal "0", get_statement_timeout
          end

          assert_equal "20ms", get_statement_timeout
        end
      end

      assert_equal "10ms", get_statement_timeout
    ensure
      set_statement_timeout(prev_value)
    end

    private
      def column_for(table_name, column_name)
        @connection.columns(table_name).find { |c| c.name == column_name.to_s }
      end

      def get_statement_timeout
        @connection.select_value("SHOW statement_timeout")
      end

      def set_statement_timeout(value)
        @connection.execute("SET statement_timeout TO #{@connection.quote(value)}")
      end
  end
end
