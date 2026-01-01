class RemoveContentFromRegulations < ActiveRecord::Migration[8.1]
  def change
    remove_column :regulations, :content, :text
  end
end
