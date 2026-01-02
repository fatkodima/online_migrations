# frozen_string_literal: true

ActiveRecord::Schema.define do
  enable_extension "pgcrypto" # for gen_random_uuid
  enable_extension "citext"
  enable_extension "btree_gist"

  create_table :background_data_migrations, force: :cascade do |t|
    t.string :migration_name, null: false
    t.jsonb :arguments, default: [], null: false
    t.string :status, default: "enqueued", null: false
    t.string :shard
    t.string :cursor
    t.string :jid
    t.datetime :started_at
    t.datetime :finished_at
    t.bigint :tick_total
    t.bigint :tick_count, default: 0, null: false
    t.float :time_running, default: 0.0, null: false
    t.integer :max_attempts, null: false
    t.float :iteration_pause, default: 0.0, null: false
    t.string :error_class
    t.string :error_message
    t.string :backtrace, array: true
    t.string :connection_class_name
    t.timestamps

    t.index [:migration_name, :arguments, :shard],
      unique: true, name: :index_background_data_migrations_on_unique_configuration
  end

  create_table :background_schema_migrations, force: :cascade do |t|
    t.string :migration_name, null: false
    t.string :table_name, null: false
    t.string :definition, null: false
    t.string :status, default: "enqueued", null: false
    t.string :shard
    t.integer :statement_timeout
    t.datetime :started_at
    t.datetime :finished_at
    t.integer :max_attempts, null: false
    t.integer :attempts, default: 0, null: false
    t.string :error_class
    t.string :error_message
    t.string :backtrace, array: true
    t.string :connection_class_name
    t.timestamps

    t.index [:migration_name, :table_name, :shard, :connection_class_name], unique: true,
      name: :index_background_schema_migrations_on_unique_configuration
  end
end
