class RenameGarmentTypeToProductTypeInAnalyses < ActiveRecord::Migration[8.1]
  def change
    rename_column :analyses, :garment_type, :product_type
  end
end
