# frozen_string_literal: true

require "test_helper"

module CommandChecker
  class AddReferenceTest < MiniTest::Test
    def setup
      @connection = ActiveRecord::Base.connection
      @connection.create_table(:users, force: :cascade)
      @connection.create_table(:projects, force: :cascade)
    end

    def teardown
      @connection.drop_table(:projects) rescue nil
      @connection.drop_table(:users) rescue nil
    end

    class AddReferenceDefault < TestMigration
      def change
        add_reference :projects, :user
      end
    end

    def test_add_reference_default
      if ar_version >= 5.0
        assert_unsafe AddReferenceDefault, <<~MSG
          Adding an index non-concurrently blocks writes.
          Instead, use add_reference_concurrently helper. It will create a reference and take care of safely adding index.

          class CommandChecker::AddReferenceTest::AddReferenceDefault < #{migration_parent_string}
            disable_ddl_transaction!

            def change
              add_reference_concurrently :projects, :user
            end
          end
        MSG
      else
        assert_safe AddReferenceDefault
      end
    end

    class AddReferenceIndex < TestMigration
      def change
        add_reference :projects, :user, index: true
      end
    end

    def test_add_reference_index
      assert_unsafe AddReferenceIndex
    end

    class AddReferenceNoIndex < TestMigration
      def change
        add_reference :projects, :user, index: false
      end
    end

    def test_add_reference_no_index
      assert_safe AddReferenceNoIndex
    end

    class AddReferenceIndexConcurrently < TestMigration
      disable_ddl_transaction!

      def change
        add_reference :projects, :user, index: { algorithm: :concurrently }
      end
    end

    def test_add_reference_index_concurrently
      assert_safe AddReferenceIndexConcurrently
    end

    class AddReferenceForeignKey < TestMigration
      def change
        add_reference :projects, :user, index: false, foreign_key: true
      end
    end

    def test_add_reference_foreign_key
      assert_unsafe AddReferenceForeignKey, <<~MSG
        Adding a foreign key blocks writes on both tables.
        Instead, use add_reference_concurrently helper. It will create a reference and take care of safely adding a foreign key.

        class CommandChecker::AddReferenceTest::AddReferenceForeignKey < #{migration_parent_string}
          disable_ddl_transaction!

          def change
            add_reference_concurrently :projects, :user, index: false, foreign_key: true
          end
        end
      MSG
    end

    class AddReferenceForeignKeyNoValidate < TestMigration
      def change
        add_reference :projects, :user, index: false, foreign_key: { validate: false }
      end
    end

    def test_add_reference_foreign_key_no_validate
      assert_safe AddReferenceForeignKeyNoValidate
    end

    class AddReferenceForeignKeyValidate < TestMigration
      def change
        add_reference :projects, :user, index: false, foreign_key: { validate: true }
      end
    end

    def test_add_reference_foreign_key_validate
      assert_unsafe AddReferenceForeignKeyValidate
    end

    class AddReferenceIndexAndForeignKey < TestMigration
      def change
        add_reference :projects, :user, index: true, foreign_key: true
      end
    end

    def test_add_reference_index_and_foreign_key
      assert_unsafe AddReferenceIndexAndForeignKey, <<~MSG
        Adding a foreign key blocks writes on both tables.
        Adding an index non-concurrently blocks writes.
        Instead, use add_reference_concurrently helper. It will create a reference and take care of safely adding a foreign key and index.
      MSG
    end

    class AddReferenceForeignKeyFromNewTable < TestMigration
      def change
        create_table :new_projects
        add_reference :new_projects, :user, index: false, foreign_key: true
      end
    end

    def test_add_reference_foreign_key_from_new_table
      assert_safe AddReferenceForeignKeyFromNewTable
    end

    # add_belongs_to is an alias for add_reference, so it is covered by the latter
    class AddBelongsTo < TestMigration
      def change
        add_belongs_to :projects, :user, index: true
      end
    end

    def test_add_belongs_to
      assert_unsafe AddBelongsTo, "add_reference_concurrently"
    end
  end
end
