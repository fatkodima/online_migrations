# frozen_string_literal: true

require "test_helper"

module SchemaStatements
  class RenamingTableTest < Minitest::Test
    class ProjectOld < ActiveRecord::Base
      self.table_name = "projects"
    end

    class ProjectNew < ActiveRecord::Base
      self.table_name = "projects_new"
    end

    def setup
      OnlineMigrations.config.table_renames["projects"] = "projects_new"

      @connection = ActiveRecord::Base.connection
      @schema_cache = @connection.schema_cache

      @connection.create_table(:projects, force: true) do |t|
        t.string :name, index: true
      end
    end

    def teardown
      # Reset table/column renames.
      OnlineMigrations.config.table_renames.clear
      @connection.schema_cache.clear!

      @connection.execute("DROP VIEW projects") rescue nil
      @connection.drop_table(:projects, if_exists: true)
      @connection.drop_table(:projects_new, if_exists: true)
    end

    def test_table_is_not_renamed
      ProjectOld.reset_column_information
      @connection.schema_cache.clear!

      assert_equal "id", ProjectOld.primary_key
    end

    def test_rename_table_while_old_code_is_running
      @schema_cache.clear!
      ProjectOld.reset_column_information

      # Fill the SchemaCache
      ProjectOld.columns_hash
      ProjectOld.primary_key

      # Need to run SQL directly, because rename_column
      # used in initialize_table_rename clears SchemaCache
      @connection.execute("ALTER TABLE projects RENAME TO projects_new")
      @connection.execute("CREATE VIEW projects AS SELECT * FROM projects_new")

      project = ProjectOld.create!
      assert project.persisted?
    end

    def test_old_code_uses_new_table_for_metadata
      @connection.initialize_table_rename(:projects, :projects_new)
      ProjectOld.reset_column_information
      ProjectNew.reset_column_information
      @schema_cache.clear!

      assert_equal ProjectNew.primary_key, ProjectOld.primary_key

      assert_not_empty ProjectOld.columns
      assert_equal ProjectNew.columns, ProjectOld.columns

      assert_not_empty ProjectOld.columns_hash
      assert_equal ProjectNew.columns_hash, ProjectOld.columns_hash

      assert_not_empty @schema_cache.indexes("projects")
      assert_equal @schema_cache.indexes("projects_new"), @schema_cache.indexes("projects")
    end

    def test_old_code_and_new_code_accepts_crud_operations
      @connection.initialize_table_rename(:projects, :projects_new)
      ProjectOld.reset_column_information
      ProjectNew.reset_column_information
      @schema_cache.clear!

      project_old = ProjectOld.create!
      assert_equal ProjectNew.last.id, project_old.id

      project_new = ProjectNew.create!
      assert_equal ProjectOld.last.id, project_new.id
    end

    def test_revert_initialize_table_rename
      @connection.initialize_table_rename(:projects, :projects_new)

      assert_sql(
        'DROP VIEW IF EXISTS "projects"',
        'ALTER TABLE "projects_new" RENAME TO "projects"'
      ) do
        @connection.revert_initialize_table_rename(:projects, :projects_new)
      end
    end

    def test_finalize_table_rename
      @connection.initialize_table_rename(:projects, :projects_new)

      assert_sql('DROP VIEW IF EXISTS "projects"') do
        @connection.finalize_table_rename(:projects)
      end
    end

    def test_revert_finalize_table_rename
      @connection.initialize_table_rename(:projects, :projects_new)
      @connection.finalize_table_rename(:projects)

      assert_sql('CREATE VIEW "projects" AS SELECT * FROM "projects_new"') do
        @connection.revert_finalize_table_rename(:projects, :projects_new)
      end
    end

    # Test that it is properly reset in rails tests using fixtures.
    def test_initialize_table_rename_and_resetting_sequence
      @connection.initialize_table_rename(:projects, :projects_new)

      @schema_cache.clear!
      ProjectNew.reset_column_information

      _project1 = ProjectNew.create!(id: 100_000, name: "Old")
      @connection.reset_pk_sequence!("projects")
      project2 = ProjectNew.create!(name: "New")
      assert_equal project2, ProjectNew.last
    end
  end
end
