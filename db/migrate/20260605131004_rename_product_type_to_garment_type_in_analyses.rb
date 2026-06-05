class RenameProductTypeToGarmentTypeInAnalyses < ActiveRecord::Migration[8.1]
  def change
    rename_column :analyses, :product_type, :garment_type
  end
end
