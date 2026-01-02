class CreateRegulations < ActiveRecord::Migration[8.1]
  def change
    create_table :regulations do |t|
      t.references :agency, null: false, foreign_key: true
      t.integer :cfr_title, null: false
      t.string :part
      t.string :section
      t.text :content, null: false
      t.integer :word_count, default: 0
      t.date :last_amended_on
      t.string :version_hash
      t.integer :hierarchy_depth, default: 0
      t.integer :cross_reference_count, default: 0
      t.jsonb :metadata, default: {}

      t.timestamps
    end

    add_index :regulations, [ :agency_id, :cfr_title ]
    add_index :regulations, [ :cfr_title, :part, :section ], unique: true
    add_index :regulations, :last_amended_on
  end
end
