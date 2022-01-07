# frozen_string_literal: true

require "test_helper"

module CommandChecker
  class MiscTest < MiniTest::Test
    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users, force: :cascade)
      @connection.create_table(:projects, force: :cascade)
    end

    def teardown
      @connection.drop_table(:projects) rescue nil
      @connection.drop_table(:users) rescue nil
    end

    class ForceCreateTable < TestMigration
      def change
        create_table :users, force: true
      end
    end

    def test_force_create_table
      assert_unsafe ForceCreateTable
    end

    class ForceCreateJoinTable < TestMigration
      def change
        create_join_table :users, :projects, force: true
      end
    end

    def test_force_create_join_table
      assert_unsafe ForceCreateJoinTable
    end

    class RenameColumn < TestMigration
      def change
        rename_column :users, :name, :first_name
      end
    end

    def test_rename_column
      assert_unsafe RenameColumn, <<~MSG
        Renaming a column that's in use will cause errors in your application.
        migration_helpers provides a safer approach to do this:

        1. Instruct Rails that you are going to rename a column:

          OnlineMigrations.config.column_renames = {
            "users" => {
              "name" => "first_name"
            }
          }

        2. Deploy
        3. Tell the database that you are going to rename a column. This will not actually rename any columns,
        nor any data/indexes/foreign keys copying will be made, so will be instantaneous.
        It will use a combination of a VIEW and column aliasing to work with both column names simultaneously:

          class InitializeCommandChecker::MiscTest::RenameColumn < #{migration_parent_string}
            def change
              initialize_column_rename :users, :name, :first_name
            end
          end

        4. Replace usages of the old column with a new column in the codebase
        5. Deploy
        6. Remove the column rename config from step 1
        7. Remove the VIEW created in step 3:

          class FinalizeCommandChecker::MiscTest::RenameColumn < #{migration_parent_string}
            def change
              finalize_column_rename :users, :name, :first_name
            end
          end

        8. Deploy
      MSG
    end

    def test_rename_column_without_partial_writes
      without_partial_writes do
        assert_unsafe RenameColumn, <<~MSG
          NOTE: You also need to temporarily enable partial writes until the process of column rename is fully done.
          # config/application.rb
          config.active_record.#{OnlineMigrations::Utils.ar_partial_writes_setting} = true
        MSG
      end
    end

    class RenameColumnNewTable < TestMigration
      def change
        create_table :users_new do |t|
          t.string :name
        end
        rename_column :users_new, :name, :first_name
      end
    end

    class ExecuteQuery < TestMigration
      def change
        execute("SELECT 1")
      end
    end

    def test_execute_query
      assert_unsafe ExecuteQuery, <<~MSG
        Online Migrations does not support inspecting what happens inside an
        execute call, so cannot help you here. Make really sure that what
        you're doing is safe before proceeding, then wrap it in a safety_assured { ... } block.
      MSG
    end

    class ExecuteQuerySafetyAssured < TestMigration
      def up
        safety_assured { execute("SELECT 1") }
      end

      def down; end
    end

    def test_execute_query_safety_assured
      assert_safe ExecuteQuerySafetyAssured
    end

    private
      def without_partial_writes
        setting = OnlineMigrations::Utils.ar_partial_writes_setting
        ActiveRecord::Base.public_send("#{setting}=", false)
      ensure
        ActiveRecord::Base.public_send("#{setting}=", true)
      end
  end
end
