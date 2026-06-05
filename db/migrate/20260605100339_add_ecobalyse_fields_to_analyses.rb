class AddEcobalyseFieldsToAnalyses < ActiveRecord::Migration[8.1]
  def change
    add_column :analyses, :ecobalyse_fields, :jsonb
  end
end
