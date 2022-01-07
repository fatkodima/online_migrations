# frozen_string_literal: true

require "test_helper"

module SchemaStatements
  class RenamingTableTest < MiniTest::Test
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
      @connection.drop_table(:projects) rescue nil
      @connection.drop_table(:projects_new) rescue nil
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

      milestone = ProjectOld.create!
      assert milestone.persisted?
    end

    def test_old_code_uses_new_table_for_metadata
      @connection.initialize_table_rename(:projects, :projects_new)
      ProjectOld.reset_column_information
      ProjectNew.reset_column_information
      @schema_cache.clear!

      assert_equal ProjectNew.primary_key, ProjectOld.primary_key

      refute_empty ProjectOld.columns
      assert_equal ProjectNew.columns, ProjectOld.columns

      refute_empty ProjectOld.columns_hash
      assert_equal ProjectNew.columns_hash, ProjectOld.columns_hash

      if ar_version >= 6.0
        refute_empty @schema_cache.indexes("projects")
        assert_equal @schema_cache.indexes("projects_new"), @schema_cache.indexes("projects")
      end
    end

    def test_old_code_and_new_code_accepts_crud_operations
      @connection.initialize_table_rename(:projects, :projects_new)
      ProjectOld.reset_column_information
      ProjectNew.reset_column_information
      @schema_cache.clear!

      milestone_old = ProjectOld.create!
      assert_equal ProjectNew.last.id, milestone_old.id

      milestone_new = ProjectNew.create!
      assert_equal ProjectOld.last.id, milestone_new.id
    end

    def test_revert_initialize_table_rename
      @connection.initialize_table_rename(:projects, :projects_new)

      assert_sql(
        "DROP VIEW IF EXISTS projects",
        'ALTER TABLE "projects_new" RENAME TO "projects"'
      ) do
        @connection.revert_initialize_table_rename(:projects, :projects_new)
      end
    end

    def test_finalize_table_rename
      @connection.initialize_table_rename(:projects, :projects_new)

      assert_sql("DROP VIEW IF EXISTS projects") do
        @connection.finalize_table_rename(:projects)
      end
    end

    def test_revert_finalize_table_rename
      @connection.initialize_table_rename(:projects, :projects_new)
      @connection.finalize_table_rename(:projects)

      assert_sql("CREATE VIEW projects AS SELECT * FROM projects_new") do
        @connection.revert_finalize_table_rename(:projects, :projects_new)
      end
    end
  end
end
