class AddCfrReferencesToAgencies < ActiveRecord::Migration[8.1]
  def change
    add_column :agencies, :cfr_references, :jsonb, default: []
  end
end
