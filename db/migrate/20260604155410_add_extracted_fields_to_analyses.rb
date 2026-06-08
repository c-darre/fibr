class AddExtractedFieldsToAnalyses < ActiveRecord::Migration[8.1]
  def change
    add_column :analyses, :extracted_fields, :jsonb
  end
end
