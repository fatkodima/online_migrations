# frozen_string_literal: true

require "test_helper"

module SchemaStatements
  class RenamingColumnTest < MiniTest::Test
    class Project < ActiveRecord::Base
    end

    def setup
      OnlineMigrations.config.column_renames["projects"] = { "name" => "name_new" }

      @connection = ActiveRecord::Base.connection
      @schema_cache = @connection.schema_cache

      @connection.create_table(:projects, force: true) do |t|
        t.string :name, index: true
      end
    end

    def teardown
      # Reset table/column renames.
      OnlineMigrations.config.column_renames.clear
      @schema_cache.clear!

      @connection.execute("DROP VIEW projects") rescue nil
      @connection.drop_table(:projects) rescue nil

      # For ActiveRecord 5.0+ we can use if_exists: true for drop_table
      @connection.drop_table(:projects_column_rename) rescue nil
    end

    def test_column_is_not_renamed
      Project.reset_column_information
      @schema_cache.clear!

      assert_equal :string, Project.columns_hash["name"].type
    end

    def test_rename_column_while_old_code_is_running
      @schema_cache.clear!
      Project.reset_column_information

      # Fill the SchemaCache
      Project.columns_hash
      Project.primary_key

      # Need to run SQL directly, because rename_table
      # used in initialize_column_rename clears SchemaCache
      @connection.execute("ALTER TABLE projects RENAME TO projects_column_rename")
      @connection.execute("CREATE VIEW projects AS SELECT *, name AS name_new FROM projects_column_rename")

      project = Project.create!(name: "Name")
      assert project.persisted?
      assert_equal "Name", project.name
    end

    def test_old_code_reloads_after_rename_column
      # Need to run SQL directly, because rename_table
      # used in initialize_column_rename clears SchemaCache
      @connection.execute("ALTER TABLE projects RENAME TO projects_column_rename")
      @connection.execute("CREATE VIEW projects AS SELECT *, name AS name_new FROM projects_column_rename")

      @schema_cache.clear!
      Project.reset_column_information

      project = Project.create!(name: "Name")
      assert project.persisted?
      assert_equal "Name", project.name
    end

    def test_old_code_uses_original_table_for_metadata
      @connection.initialize_column_rename(:projects, :name, :name_new)
      Project.reset_column_information
      @schema_cache.clear!

      assert_equal "id", Project.primary_key

      refute_empty Project.columns
      refute_empty Project.columns_hash

      if ar_version >= 6.0
        refute_empty @schema_cache.indexes("projects")
      end
    end

    def test_old_code_accepts_crud_operations
      Project.reset_column_information
      @schema_cache.clear!

      # Fill the SchemaCache
      Project.columns_hash
      Project.primary_key

      # Need to run SQL directly, because rename_table
      # used in initialize_column_rename clears SchemaCache
      @connection.execute("ALTER TABLE projects RENAME TO projects_column_rename")
      @connection.execute("CREATE VIEW projects AS SELECT *, name AS name_new FROM projects_column_rename")

      project_old = Project.create!(name: "Name")
      assert_equal Project.last.id, project_old.id
      assert_equal "Name", project_old.name
    end

    def test_new_code_accepts_crud_operations
      @connection.initialize_column_rename(:projects, :name, :name_new)
      Project.reset_column_information
      @schema_cache.clear!

      project = Project.create!(name_new: "Name")
      assert_equal Project.last.id, project.id
      assert_equal "Name", project.name_new
    end

    def test_revert_initialize_column_rename
      @connection.initialize_column_rename(:projects, :name, :name_new)

      assert_sql(
        "DROP VIEW projects",
        'ALTER TABLE "projects_column_rename" RENAME TO "projects"'
      ) do
        @connection.revert_initialize_column_rename(:projects)
      end
    end

    def test_finalize_column_rename
      @connection.initialize_column_rename(:projects, :name, :name_new)

      assert_sql(
        "DROP VIEW projects",
        'ALTER TABLE "projects_column_rename" RENAME TO "projects"',
        'ALTER TABLE "projects" RENAME COLUMN "name" TO "name_new"'
      ) do
        @connection.finalize_column_rename(:projects, :name, :name_new)
      end
    end

    def test_revert_finalize_column_rename
      @connection.initialize_column_rename(:projects, :name, :name_new)
      @connection.finalize_column_rename(:projects, :name, :name_new)

      assert_sql(
        'ALTER TABLE "projects" RENAME COLUMN "name_new" TO "name"',
        'ALTER TABLE "projects" RENAME TO "projects_column_rename"',
        "CREATE VIEW projects AS SELECT *, name AS name_new FROM projects_column_rename"
      ) do
        @connection.revert_finalize_column_rename(:projects, :name, :name_new)
      end
    end

    # Test that it is properly reset in rails tests using fixtures.
    def test_initialize_column_rename_and_resetting_sequence
      skip("Rails 4.2 is not working with newer PostgreSQL") if ar_version <= 4.2

      @connection.initialize_column_rename(:projects, :name, :name_new)

      @schema_cache.clear!
      Project.reset_column_information

      _project1 = Project.create!(id: 100_000, name: "Old")
      @connection.reset_pk_sequence!("projects")
      project2 = Project.create!(name: "New")
      assert_equal project2, Project.last
    end
  end
end
