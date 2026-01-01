class CreateRegulationVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :regulation_versions do |t|
      t.references :regulation, null: false, foreign_key: true, index: true

      # Temporal dimensions
      t.date :effective_date, null: false
      t.date :superseded_at
      t.timestamp :synced_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }

      # Content
      t.text :content, null: false
      t.string :content_hash, null: false, limit: 64

      # Metrics (denormalized for performance)
      t.integer :word_count, default: 0
      t.integer :section_count, default: 0
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    # Performance indexes
    add_index :regulation_versions, :content_hash
    add_index :regulation_versions, :effective_date

    # Prevent duplicate effective dates for same regulation
    add_index :regulation_versions,
      [:regulation_id, :effective_date],
      unique: true,
      name: 'idx_unique_reg_effective_dates'

    # Partial index for current versions (most queries)
    add_index :regulation_versions,
      [:regulation_id, :superseded_at],
      where: 'superseded_at IS NULL',
      name: 'idx_current_versions'

    # Temporal range queries
    add_index :regulation_versions,
      [:effective_date, :superseded_at],
      name: 'idx_temporal_range'
  end
end
