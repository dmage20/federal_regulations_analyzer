class CreateAgencies < ActiveRecord::Migration[8.1]
  def change
    create_table :agencies do |t|
      t.string :name, null: false
      t.string :acronym, null: false
      t.text :description
      t.integer :cfr_titles, array: true, default: []
      t.bigint :total_word_count, default: 0
      t.string :content_checksum
      t.datetime :last_synced_at
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :agencies, :acronym, unique: true
    add_index :agencies, :name
  end
end
