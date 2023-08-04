# frozen_string_literal: true

require "test_helper"

module CommandChecker
  class CustomChecksTest < Minitest::Test
    def setup
      @connection = ActiveRecord::Base.connection

      @connection.create_table(:users, force: :cascade)
      @connection.create_table(:projects, force: :cascade)
    end

    def teardown
      @connection.drop_table(:users) rescue nil
      @connection.drop_table(:projects) rescue nil
    end

    class AddBioToUsers < TestMigration
      def change
        add_column :users, :bio, :text
      end
    end

    def test_custom_check_applies
      with_custom_check do
        assert_unsafe AddBioToUsers, "No more columns on the users table"
      end
    end

    class AddStarCountToProjects < TestMigration
      def change
        add_column :projects, :star_count, :integer
      end
    end

    def test_custom_check_does_not_apply
      with_custom_check do
        assert_safe AddStarCountToProjects
      end
    end

    def test_custom_check_start_after
      with_custom_check(start_after: 20210101000001) do
        assert_safe AddBioToUsers
      end
    end

    private
      def with_custom_check(**options)
        OnlineMigrations.config.add_check(**options) do |method, args|
          if method == :add_column && args[0].to_s == "users"
            stop!("No more columns on the users table")
          end
        end

        yield
      ensure
        OnlineMigrations.config.checks.clear
      end
  end
end
