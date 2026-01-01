class AddTotalRestrictionsCountToAgencies < ActiveRecord::Migration[8.1]
  def change
    add_column :agencies, :total_restrictions_count, :integer, default: 0
  end
end
