# frozen_string_literal: true

module MinitestHelpers
  def assert_raises_with_message(exception_class, message, &block)
    error = assert_raises(exception_class, &block)
    assert_match message, error.message
  end

  def assert_nothing_raised
    yield
    assert true # rubocop:disable Minitest/UselessAssertion
  rescue => e
    raise Minitest::UnexpectedError.new(e) # rubocop:disable Style/RaiseArgs
  end

  def migrate(migration, direction: :up, version: 1)
    connection = ActiveRecord::Base.connection

    if OnlineMigrations::Utils.ar_version >= 7.2
      ActiveRecord::SchemaMigration.new(connection.pool).delete_all_versions
    else
      ActiveRecord::SchemaMigration.new(connection).delete_all_versions
    end

    migration.version ||= version

    if direction == :down
      if OnlineMigrations::Utils.ar_version >= 7.2
        ActiveRecord::SchemaMigration.new(connection.pool).create_version(migration.version)
      else
        ActiveRecord::SchemaMigration.new(connection).create_version(migration.version)
      end
    end

    args =
      if OnlineMigrations::Utils.ar_version >= 7.2
        [ActiveRecord::SchemaMigration.new(connection.pool), ActiveRecord::InternalMetadata.new(connection.pool)]
      else
        [ActiveRecord::SchemaMigration.new(connection), ActiveRecord::InternalMetadata.new(connection)]
      end
    ActiveRecord::Migrator.new(direction, [migration], *args).migrate
    true
  end

  def assert_safe(migration, direction: nil, **options)
    if direction
      assert migrate(migration, direction: direction, **options)
    else
      assert migrate(migration, direction: :up, **options)
      assert migrate(migration, direction: :down, **options)
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
    query_cb = ->(*, payload) { queries << payload[:sql] if !["TRANSACTION"].include?(payload[:name]) }
    ActiveSupport::Notifications.subscribed(query_cb, "sql.active_record", &block)
    queries
  end

  def assert_sql(*patterns_to_match, &block)
    queries = track_queries(&block)

    failed_patterns = []
    patterns_to_match.each do |pattern|
      pattern = pattern.downcase
      failed_patterns << pattern if queries.none? { |sql| sql.downcase.squish.include?(pattern) }
    end

    message = "Query pattern(s) #{failed_patterns.map(&:inspect).join(', ')} not found."
    message += "\nQueries:\n#{queries.join("\n")}" if queries.any?

    assert_empty failed_patterns, message
  end

  def refute_sql(*patterns_to_match, &block)
    queries = track_queries(&block)

    failed_patterns = []
    patterns_to_match.each do |pattern|
      pattern = pattern.downcase
      failed_patterns << pattern if queries.any? { |sql| sql.downcase.include?(pattern) }
    end

    message = "Query pattern(s) #{failed_patterns.map(&:inspect).join(', ')} not found."
    message += "\nQueries:\n#{queries.join("\n")}" if queries.any?

    assert_empty failed_patterns, message
  end

  def stub_const(mod, constant, new_value)
    old_value = mod.const_get(constant, false)
    mod.send(:remove_const, constant)
    mod.const_set(constant, new_value)
    yield
  ensure
    mod.send(:remove_const, constant)
    mod.const_set(constant, old_value)
  end

  def with_target_version(version)
    prev = OnlineMigrations.config.target_version
    OnlineMigrations.config.target_version = version
    yield
  ensure
    OnlineMigrations.config.target_version = prev
  end

  def with_safety_assured(&block)
    OnlineMigrations::CommandChecker.stub(:safe, true, &block)
  end

  def with_partial_writes(value, &block)
    ActiveRecord::Base.stub(:partial_inserts, value, &block)
  end

  def ar_version
    OnlineMigrations::Utils.ar_version
  end

  def migration_parent
    "ActiveRecord::Migration[#{OnlineMigrations::Utils.ar_version}]"
  end

  def load_schema(version)
    load File.expand_path("db/version_#{version}.rb", __dir__)
  end

  def on_each_shard(&block)
    on_shard(:shard_one, &block)
    on_shard(:shard_two, &block)
  end

  def on_shard(shard, &block)
    ShardRecord.connected_to(shard: shard, role: :writing, &block)
  end

  def last_schema_migration
    OnlineMigrations::BackgroundSchemaMigrations::Migration.last
  end
end

Minitest::Test.class_eval do
  include MinitestHelpers
  alias_method :assert_not, :refute
  alias_method :assert_not_equal, :refute_equal
  alias_method :assert_not_includes, :refute_includes
  alias_method :assert_no_match, :refute_match
  alias_method :assert_not_nil, :refute_nil
  alias_method :assert_not_empty, :refute_empty

  def after_teardown
    Sidekiq::Worker.clear_all
    super
  end
end
