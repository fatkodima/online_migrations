# frozen_string_literal: true

require "test_helper"

module SchemaStatements
  class ChangingColumnTypeTest < MiniTest::Test
    class User < ActiveRecord::Base
    end

    class Project < ActiveRecord::Base
      belongs_to :user
    end

    def setup
      @connection = ActiveRecord::Base.connection

      @connection.create_table(:users, id: :serial, force: :cascade)

      @connection.create_table(:projects, id: :serial, force: :cascade) do |t|
        t.text :name, default: "My project"
        t.string :description, null: false
        t.text :settings
        t.bigint :star_count
        t.integer :user_id

        t.index :name
        t.foreign_key :users
      end

      @connection.add_check_constraint(:projects, "star_count >= 0")

      User.reset_column_information
      Project.reset_column_information
    end

    def teardown
      OnlineMigrations::BackgroundMigrations::Migration.delete_all
      @connection.drop_table(:projects) rescue nil
      @connection.drop_table(:users) rescue nil
    end

    def test_initialize_column_type_change_creates_new_column
      @connection.initialize_column_type_change(:projects, :name, :string, limit: 100)

      column = column_for(:projects, :name_for_type_change)
      assert_equal :string, column.type
      assert_equal 100, column.limit
      assert column.null
      assert_equal "My project", column.default
    end

    def test_initialize_columns_type_change_creates_new_columns
      @connection.initialize_columns_type_change(:projects, [[:name, :string], [:user_id, :bigint]], name: { limit: 100 })

      name_column = column_for(:projects, :name_for_type_change)
      assert_equal :string, name_column.type
      assert_equal 100, name_column.limit
      assert name_column.null
      assert_equal "My project", name_column.default

      user_id_column = column_for(:projects, :user_id_for_type_change)
      assert user_id_column.null
      assert_equal "bigint", user_id_column.sql_type
    end

    def test_initialize_columns_type_change_raises_for_incorrect_column_and_type_format
      error = assert_raises(ArgumentError) do
        @connection.initialize_columns_type_change(:projects, [:name, :string])
      end
      assert_equal "columns_and_types must be an array of arrays", error.message
    end

    def test_initialize_columns_type_change_raises_for_incorrect_options_keys
      error = assert_raises(ArgumentError) do
        @connection.initialize_columns_type_change(:projects, [[:name, :string], [:user_id, :bigint]],
            name: { limit: 100 }, not_a_column: { something: 42 })
      end
      assert_equal "Options has unknown keys: :not_a_column. Can contain only column names: :name, :user_id.", error.message
    end

    def test_ignores_new_column_in_schema_cache
      @connection.initialize_column_type_change(:projects, :name, :string)
      schema_cache = @connection.schema_cache
      schema_cache.clear!
      assert(schema_cache.columns(:projects).none? { |column| column.name == "name_for_type_change" })
    end

    def test_initialize_column_type_change_for_primary_key_before_11
      with_postgres(10) do
        @connection.initialize_column_type_change(:projects, :id, :bigint)

        column = column_for(:projects, :id_for_type_change)
        assert_equal "bigint", column.sql_type
        assert_nil column.default
        assert column.null
      end
    end

    def test_initialize_column_type_change_for_primary_key_after_11
      with_postgres(11) do
        @connection.initialize_column_type_change(:projects, :id, :bigint)

        column = column_for(:projects, :id_for_type_change)
        assert_equal "bigint", column.sql_type
        assert_equal "0", column.default
        assert_not column.null
      end
    end

    def test_initialize_column_type_change_copies_not_null_constraint
      @connection.initialize_column_type_change(:projects, :description, :text)

      # We need to remove copy triggers to be able to test NOT NULL constraints
      @connection.finalize_column_type_change(:projects, :description)
      @connection.cleanup_column_type_change(:projects, :description)

      assert_raises(ActiveRecord::StatementInvalid) do
        @connection.execute("INSERT INTO projects (description) VALUES (NULL)")
      end
    end

    def test_initialize_column_type_change_creates_copy_triggers
      @connection.initialize_column_type_change(:projects, :name, :string)
      clear_caches

      p = Project.create!(name: "rails", description: "MVC framework")
      assert_equal "rails", @connection.select_value("SELECT name_for_type_change FROM projects WHERE id = #{p.id}")
    end

    def test_revert_initialize_column_type_change
      @connection.initialize_column_type_change(:projects, :name, :string)
      assert @connection.column_exists?(:projects, :name_for_type_change)

      @connection.revert_initialize_column_type_change(:projects, :name)
      assert_not @connection.column_exists?(:projects, :name_for_type_change)
    end

    def test_revert_initialize_columns_type_change
      @connection.initialize_columns_type_change(:projects, [[:name, :string], [:user_id, :bigint]])
      assert @connection.column_exists?(:projects, :name_for_type_change)
      assert @connection.column_exists?(:projects, :user_id_for_type_change)

      @connection.revert_initialize_columns_type_change(:projects, [[:name, :string], [:user_id, :bigint]])
      assert_not @connection.column_exists?(:projects, :name_for_type_change)
      assert_not @connection.column_exists?(:projects, :user_id_for_type_change)
    end

    def test_backfill_column_for_type_change_updates_existing_data
      clear_caches
      p = Project.create!(name: "rails", description: "MVC framework")

      @connection.initialize_column_type_change(:projects, :name, :string)
      @connection.backfill_column_for_type_change(:projects, :name)
      assert_equal "rails", @connection.select_value("SELECT name_for_type_change FROM projects WHERE id = #{p.id}")
    end

    def test_backfill_columns_for_type_change_updates_existing_data
      clear_caches
      u = User.create!
      p = Project.create!(name: "rails", description: "MVC framework", user: u)

      @connection.initialize_columns_type_change(:projects, [[:name, :string], [:user_id, :bigint]])
      @connection.backfill_columns_for_type_change(:projects, :name, :user_id)

      result = @connection.select_rows("SELECT name_for_type_change, user_id_for_type_change FROM projects WHERE id = #{p.id}").first
      if ar_version <= 4.2
        assert_equal ["rails", u.id.to_s], result
      else
        assert_equal ["rails", u.id], result
      end
    end

    def test_backfill_column_for_type_change_type_cast_function
      clear_caches
      p = Project.create!(description: "Required description", settings: '{"key":"value"}')

      change_column_type(:projects, :settings, :jsonb, type_cast_function: "jsonb")
      Project.reset_column_information
      assert_equal "value", p.reload.settings["key"]
    end

    def test_backfill_column_for_type_change_in_background
      @connection.initialize_column_type_change(:projects, :name, :string)
      m = @connection.backfill_column_for_type_change_in_background(
        :projects, :name, model_name: Project, type_cast_function: "jsonb"
      )

      assert_equal "CopyColumn", m.migration_name
      assert_equal ["projects", ["name"], ["name_for_type_change"], "SchemaStatements::ChangingColumnTypeTest::Project", { "name" => "jsonb" }], m.arguments
    end

    def test_backfill_columns_for_type_change_in_background
      @connection.initialize_columns_type_change(:projects, [[:name, :string], [:description, :text]])
      m = @connection.backfill_columns_for_type_change_in_background(
        :projects, :name, :description, model_name: Project, type_cast_functions: { "name" => "jsonb" }
      )

      assert_equal "CopyColumn", m.migration_name
      assert_equal(["projects", ["name", "description"], ["name_for_type_change", "description_for_type_change"],
                    "SchemaStatements::ChangingColumnTypeTest::Project", { "name" => "jsonb" }], m.arguments)
    end

    def test_finalize_column_type_change_raises_in_transaction
      assert_raises_in_transaction do
        @connection.finalize_column_type_change(:projects, :name)
      end
    end

    def test_finalize_column_type_change_copies_indexes
      @connection.initialize_column_type_change(:projects, :name, :string)
      @connection.finalize_column_type_change(:projects, :name)
      assert_equal(1, @connection.indexes(:projects).count { |index| index.columns.include?("name_for_type_change") })
    end

    def test_finalize_column_type_change_copies_foreign_key
      @connection.initialize_column_type_change(:projects, :user_id, :bigint)
      @connection.finalize_column_type_change(:projects, :user_id)
      assert @connection.foreign_key_exists?(:projects, to_table: :users, column: :user_id_for_type_change)
    end

    def test_finalize_column_type_change_copies_check_constraints
      @connection.initialize_column_type_change(:projects, :star_count, :integer)
      @connection.finalize_column_type_change(:projects, :star_count)

      user = User.create!

      assert_raises(ActiveRecord::StatementInvalid) do
        @connection.execute <<-SQL.strip_heredoc
          INSERT INTO projects (description, user_id, star_count)
          VALUES ('Description', #{user.id}, -1)
        SQL
      end
    end

    def test_finalize_column_type_change_keeps_columns_in_sync
      @connection.initialize_column_type_change(:projects, :id, :bigint)
      @connection.finalize_column_type_change(:projects, :id)

      project = Project.create!(description: "Description")
      # We need to perform a direct SQL, since `_for_type_change` colums are ignored by SchemaCache.
      old_id = @connection.select_value("SELECT id_for_type_change FROM projects WHERE id = #{project.id}").to_i
      assert_equal project.id, old_id
    end

    def test_finalize_columns_type_change
      @connection.initialize_columns_type_change(:projects, [[:id, :bigint], [:name, :string]])
      @connection.finalize_columns_type_change(:projects, :id, :name)

      id_column = column_for(:projects, :id)
      assert_equal "bigint", id_column.sql_type

      name_column = column_for(:projects, :name)
      assert_equal :string, name_column.type
    end

    def test_finalize_column_type_change_for_primary_key
      user1 = User.create!

      with_postgres(11) do
        @connection.initialize_column_type_change(:users, :id, :bigint)
        @connection.finalize_column_type_change(:users, :id)

        assert_equal "id", @connection.primary_key(:users)
        id_column = column_for(:users, :id)
        assert_equal "bigint", id_column.sql_type

        old_id_column = column_for(:users, :id_for_type_change)
        assert_equal :integer, old_id_column.type

        # sequence is assigned to the new column
        user2 = User.create!
        assert_equal user1.id + 1, user2.id
      end
    end

    def test_finalize_column_type_change_for_primary_key_before_11
      # For PG >= 11 we set NOT NULL from the beginning.
      # This tests if manual setting as NOT NULL is working as expected.
      with_postgres(10) do
        @connection.initialize_column_type_change(:users, :id, :bigint)
        @connection.finalize_column_type_change(:users, :id)

        assert_equal "id", @connection.primary_key(:users)
        id_column = column_for(:users, :id)
        assert_equal "bigint", id_column.sql_type
      end
    end

    def test_finalize_column_type_change_for_primary_key_changes_referencing_foreign_keys
      @connection.initialize_column_type_change(:users, :id, :bigint)
      @connection.finalize_column_type_change(:users, :id)

      assert @connection.foreign_keys(:projects).any? do |fk|
        fk.to_table == "users" && fk.primary_key == "id"
      end
    end

    def test_revert_finalize_column_type_change_raises_in_transaction
      assert_raises_in_transaction do
        @connection.revert_finalize_column_type_change(:projects, :name)
      end
    end

    def test_revert_finalize_column_type_change
      @connection.initialize_column_type_change(:projects, :name, :string)
      @connection.finalize_column_type_change(:projects, :name)

      assert @connection.index_exists?(:projects, :name_for_type_change)

      @connection.revert_finalize_column_type_change(:projects, :name)
      assert_not @connection.index_exists?(:projects, :name_for_type_change)
    end

    def test_cleanup_column_type_change
      change_column_type(:projects, :name, :string)
      assert_not @connection.column_exists?(:projects, :name_for_type_change)

      column = column_for(:projects, :name)
      assert_equal :string, column.type
    end

    private
      def column_for(table_name, column_name)
        @connection.columns(table_name).find { |c| c.name == column_name.to_s }
      end

      def clear_caches
        Project.reset_column_information
        @connection.schema_cache.clear!
      end

      def change_column_type(table_name, column_name, type, **options)
        @connection.initialize_column_type_change(table_name, column_name, type, **options)
        @connection.backfill_column_for_type_change(table_name, column_name, **options)
        @connection.finalize_column_type_change(table_name, column_name)
        @connection.cleanup_column_type_change(table_name, column_name)
      end
  end
end
