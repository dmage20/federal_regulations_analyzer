class AddRegulationsCountToAgencies < ActiveRecord::Migration[8.1]
  def change
    add_column :agencies, :regulations_count, :integer, default: 0, null: false
  end
end
