class CreateSyncLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :sync_logs do |t|
      t.string :sync_type, null: false
      t.datetime :started_at, null: false
      t.datetime :completed_at
      t.string :status, null: false
      t.integer :records_processed, default: 0
      t.integer :records_created, default: 0
      t.integer :records_updated, default: 0
      t.text :error_messages
      t.jsonb :summary, default: {}

      t.timestamps
    end

    add_index :sync_logs, :status
    add_index :sync_logs, :started_at
  end
end
