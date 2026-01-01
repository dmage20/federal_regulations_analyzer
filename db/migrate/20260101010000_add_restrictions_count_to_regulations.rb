class AddRestrictionsCountToRegulations < ActiveRecord::Migration[8.1]
  def change
    add_column :regulations, :restrictions_count, :integer, default: 0
  end
end
