# frozen_string_literal: true

ActiveRecord::Schema.define do
  enable_extension "pgcrypto" # for gen_random_uuid
  enable_extension "citext"
  enable_extension "btree_gist"

  create_table :background_migrations do |t|
    t.string :migration_name, null: false
    t.jsonb :arguments, default: [], null: false
    t.string :batch_column_name, null: false
    t.bigint :min_value, null: false
    t.bigint :max_value, null: false
    t.bigint :rows_count
    t.integer :batch_size, null: false
    t.integer :sub_batch_size, null: false
    t.integer :batch_pause, null: false
    t.integer :sub_batch_pause_ms, null: false
    t.integer :batch_max_attempts, null: false
    t.string :status, default: "enqueued", null: false
    t.timestamps null: false

    t.index [:migration_name, :arguments],
      unique: true, name: :index_background_migrations_on_unique_configuration
  end

  create_table :background_migration_jobs do |t|
    t.bigint :migration_id, null: false
    t.bigint :min_value, null: false
    t.bigint :max_value, null: false
    t.integer :batch_size, null: false
    t.integer :sub_batch_size, null: false
    t.integer :pause_ms, null: false
    t.datetime :started_at
    t.datetime :finished_at
    t.string :status, default: "enqueued", null: false
    t.integer :max_attempts, null: false
    t.integer :attempts, default: 0, null: false
    t.string :error_class
    t.string :error_message
    t.string :backtrace, array: true
    t.timestamps null: false

    t.foreign_key :background_migrations, column: :migration_id, on_delete: :cascade

    t.index [:migration_id, :max_value], name: :index_background_migration_jobs_on_max_value
    t.index [:migration_id, :status, :updated_at], name: :index_background_migration_jobs_on_updated_at
    t.index [:migration_id, :finished_at], name: :index_background_migration_jobs_on_finished_at
  end
end
