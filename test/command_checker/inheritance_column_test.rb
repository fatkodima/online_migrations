# frozen_string_literal: true

require "test_helper"

module CommandChecker
  class InheritanceColumnTest < MiniTest::Test
    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users, force: :cascade)
    end

    def teardown
      @connection.drop_table(:users) rescue nil
    end

    class AddColumn < TestMigration
      def change
        add_column :users, :type, :string, default: "Member"
      end
    end

    def test_add_column
      if ar_version >= 5
        assert_unsafe AddColumn, <<-MSG.strip_heredoc
          'type' column is used for single table inheritance. Adding it might cause errors in old instances of your application.

          After the migration was ran and the column was added, but before the code is fully deployed to all instances,
          an old instance may be restarted (due to an error etc). And when it will fetch 'User' records from the database,
          'User' will look for a 'Member' subclass (from the 'type' column) and fail to locate it unless it is already defined.

          A safer approach is to:

          1. ignore the column:

            class User < #{model_parent_string}
              self.ignored_columns = ["type"]
            end

          2. deploy
          3. remove the column ignoring from step 1 and apply initial code changes
          4. deploy
        MSG
      else
        assert_unsafe AddColumn, <<-MSG.strip_heredoc
          1. ignore the column:

            class User < #{model_parent_string}
              def self.columns
                super.reject { |c| c.name == "type" }
              end
            end
        MSG
      end
    end

    class AddColumnWithDefaultHelper < TestMigration
      def change
        add_column_with_default :users, :type, :string, default: "Member"
      end
    end

    def test_add_column_with_default_helper
      assert_unsafe AddColumnWithDefaultHelper, "single table inheritance"
    end

    class AddColumnNoDefault < TestMigration
      def change
        add_column :users, :type, :string
      end
    end

    def test_add_column_no_default
      assert_safe AddColumnNoDefault
    end

    class NonInheritanceColumn < TestMigration
      def change
        add_column :users, :type, :string, default: "Member"
      end
    end

    def test_non_inheritance_column
      prev = ActiveRecord::Base.inheritance_column
      ActiveRecord::Base.inheritance_column = "my_type_column"

      assert_safe NonInheritanceColumn
    ensure
      ActiveRecord::Base.inheritance_column = prev
    end

    class CustomInheritanceColumn < TestMigration
      def change
        add_column :users, :my_type_column, :string, default: "Member"
      end
    end

    def test_custom_inheritance_column
      prev = ActiveRecord::Base.inheritance_column
      ActiveRecord::Base.inheritance_column = "my_type_column"

      if ar_version >= 5
        assert_unsafe CustomInheritanceColumn, <<-MSG.strip_heredoc
          1. ignore the column:

            class User < #{model_parent_string}
              self.ignored_columns = ["my_type_column"]
            end
        MSG
      else
        assert_unsafe CustomInheritanceColumn, <<-MSG.strip_heredoc
          1. ignore the column:

            class User < #{model_parent_string}
              def self.columns
                super.reject { |c| c.name == "my_type_column" }
              end
            end
        MSG
      end
    ensure
      ActiveRecord::Base.inheritance_column = prev
    end
  end
end
