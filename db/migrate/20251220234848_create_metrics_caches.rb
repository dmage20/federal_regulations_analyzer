class CreateMetricsCaches < ActiveRecord::Migration[8.1]
  def change
    create_table :metrics_caches do |t|
      t.references :agency, null: false, foreign_key: true
      t.string :metric_name, null: false
      t.decimal :value, precision: 15, scale: 2
      t.jsonb :details, default: {}
      t.datetime :calculated_at, null: false

      t.timestamps
    end

    add_index :metrics_caches, [ :agency_id, :metric_name ], unique: true
    add_index :metrics_caches, :metric_name
  end
end
