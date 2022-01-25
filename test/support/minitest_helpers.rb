# frozen_string_literal: true

module MinitestHelpers
  def migrate(migration, direction: :up)
    ActiveRecord::SchemaMigration.delete_all

    migration.version ||= 1

    if direction == :down
      ActiveRecord::SchemaMigration.create!(version: migration.version)
    end
    args = ActiveRecord::VERSION::MAJOR >= 6 ? [ActiveRecord::SchemaMigration] : []
    ActiveRecord::Migrator.new(direction, [migration], *args).migrate
    true
  end

  def assert_safe(migration, direction: nil)
    if direction
      assert migrate(migration, direction: direction)
    else
      assert migrate(migration, direction: :up)
      assert migrate(migration, direction: :down)
    end
  end

  def assert_unsafe(migration, message = nil, **options)
    error = assert_raises(StandardError) { migrate(migration, **options) }
    assert_instance_of OnlineMigrations::UnsafeMigration, error.cause

    puts error.message if ENV["VERBOSE"]
    assert_match(message, error.message) if message
  end

  def assert_raises_in_transaction(&block)
    error = assert_raises(RuntimeError) do
      ActiveRecord::Base.transaction(&block)
    end
    assert_match "cannot run inside a transaction", error.message
  end

  def track_queries(&block)
    queries = []
    query_cb = ->(*, payload) { queries << payload[:sql] unless ["TRANSACTION"].include?(payload[:name]) }
    ActiveSupport::Notifications.subscribed(query_cb, "sql.active_record", &block)
    queries
  end

  def assert_sql(*patterns_to_match, &block)
    queries = track_queries(&block)

    failed_patterns = []
    patterns_to_match.each do |pattern|
      failed_patterns << pattern if queries.none? { |sql| sql.include?(pattern) }
    end
    assert failed_patterns.empty?,
      "Query pattern(s) #{failed_patterns.map(&:inspect).join(', ')} not found.#{queries.empty? ? '' : "\nQueries:\n#{queries.join("\n")}"}"
  end

  def refute_sql(*patterns_to_match, &block)
    queries = track_queries(&block)

    failed_patterns = []
    patterns_to_match.each do |pattern|
      failed_patterns << pattern if queries.any? { |sql| sql.include?(pattern) }
    end
    assert failed_patterns.empty?,
      "Query pattern(s) #{failed_patterns.map(&:inspect).join(', ')} found.#{queries.empty? ? '' : "\nQueries:\n#{queries.join("\n")}"}"
  end

  def with_target_version(version)
    prev = OnlineMigrations.config.target_version
    OnlineMigrations.config.target_version = version
    yield
  ensure
    OnlineMigrations.config.target_version = prev
  end

  def with_postgres(major_version, &block)
    pg_connection = ActiveRecord::Base.connection.instance_variable_get(:@connection)
    pg_connection.stub(:server_version, major_version * 1_00_00, &block)
  end

  def ar_version
    OnlineMigrations::Utils.ar_version
  end

  def migration_parent_string
    OnlineMigrations::Utils.migration_parent_string
  end

  def model_parent_string
    OnlineMigrations::Utils.model_parent_string
  end

  def supports_multiple_dbs?
    OnlineMigrations::Utils.supports_multiple_dbs?
  end
end

Minitest::Test.class_eval do
  include MinitestHelpers
  alias_method :assert_not, :refute
end
