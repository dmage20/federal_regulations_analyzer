class DropRegulationVersions < ActiveRecord::Migration[8.1]
  def change
    drop_table :regulation_versions do |t|
      t.references :regulation, null: false, foreign_key: true
      t.text :content
      t.integer :word_count
      t.string :content_hash
      t.date :effective_date
      t.datetime :superseded_at
      t.json :metadata
      t.timestamps
    end
  end
end
