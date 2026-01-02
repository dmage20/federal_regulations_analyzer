class CreateRegulationSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :regulation_snapshots do |t|
      t.references :regulation, null: false, foreign_key: true
      t.integer :word_count, null: false, default: 0
      t.string :checksum, null: false
      t.date :snapshot_date, null: false

      t.timestamps
    end

    add_index :regulation_snapshots, [ :regulation_id, :snapshot_date ], unique: true
    add_index :regulation_snapshots, :snapshot_date
  end
end
