# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_01_01_010100) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "agencies", force: :cascade do |t|
    t.string "acronym"
    t.jsonb "cfr_references", default: []
    t.integer "cfr_titles", default: [], array: true
    t.string "content_checksum"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "last_synced_at"
    t.jsonb "metadata", default: {}
    t.string "name", null: false
    t.integer "regulations_count", default: 0, null: false
    t.integer "total_restrictions_count", default: 0
    t.bigint "total_word_count", default: 0
    t.datetime "updated_at", null: false
    t.index ["acronym"], name: "index_agencies_on_acronym", unique: true
    t.index ["name"], name: "index_agencies_on_name"
  end

  create_table "metrics_caches", force: :cascade do |t|
    t.bigint "agency_id", null: false
    t.datetime "calculated_at", null: false
    t.datetime "created_at", null: false
    t.jsonb "details", default: {}
    t.string "metric_name", null: false
    t.datetime "updated_at", null: false
    t.decimal "value", precision: 15, scale: 2
    t.index ["agency_id", "metric_name"], name: "index_metrics_caches_on_agency_id_and_metric_name", unique: true
    t.index ["agency_id"], name: "index_metrics_caches_on_agency_id"
    t.index ["metric_name"], name: "index_metrics_caches_on_metric_name"
  end

  create_table "regulation_snapshots", force: :cascade do |t|
    t.string "checksum", null: false
    t.datetime "created_at", null: false
    t.bigint "regulation_id", null: false
    t.date "snapshot_date", null: false
    t.datetime "updated_at", null: false
    t.integer "word_count", default: 0, null: false
    t.index ["regulation_id", "snapshot_date"], name: "index_regulation_snapshots_on_regulation_id_and_snapshot_date", unique: true
    t.index ["regulation_id"], name: "index_regulation_snapshots_on_regulation_id"
    t.index ["snapshot_date"], name: "index_regulation_snapshots_on_snapshot_date"
  end

  create_table "regulations", force: :cascade do |t|
    t.bigint "agency_id", null: false
    t.integer "cfr_title", null: false
    t.datetime "created_at", null: false
    t.integer "cross_reference_count", default: 0
    t.integer "hierarchy_depth", default: 0
    t.date "last_amended_on"
    t.jsonb "metadata", default: {}
    t.string "part"
    t.integer "restrictions_count", default: 0
    t.string "section"
    t.datetime "updated_at", null: false
    t.string "version_hash"
    t.integer "word_count", default: 0
    t.index ["agency_id", "cfr_title"], name: "index_regulations_on_agency_id_and_cfr_title"
    t.index ["agency_id"], name: "index_regulations_on_agency_id"
    t.index ["cfr_title", "part", "section"], name: "index_regulations_on_cfr_title_and_part_and_section", unique: true
    t.index ["last_amended_on"], name: "index_regulations_on_last_amended_on"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.datetime "created_at", null: false
    t.binary "key", null: false
    t.bigint "key_hash", null: false
    t.binary "value", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "sync_logs", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "error_messages"
    t.integer "records_created", default: 0
    t.integer "records_processed", default: 0
    t.integer "records_updated", default: 0
    t.datetime "started_at", null: false
    t.string "status", null: false
    t.jsonb "summary", default: {}
    t.string "sync_type", null: false
    t.datetime "updated_at", null: false
    t.index ["started_at"], name: "index_sync_logs_on_started_at"
    t.index ["status"], name: "index_sync_logs_on_status"
  end

  add_foreign_key "metrics_caches", "agencies"
  add_foreign_key "regulation_snapshots", "regulations"
  add_foreign_key "regulations", "agencies"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
end
