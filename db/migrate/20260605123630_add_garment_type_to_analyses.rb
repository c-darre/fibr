class AddGarmentTypeToAnalyses < ActiveRecord::Migration[8.1]
  def change
    add_column :analyses, :garment_type, :string
  end
end
