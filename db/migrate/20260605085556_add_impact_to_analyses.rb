class AddImpactToAnalyses < ActiveRecord::Migration[8.1]
  def change
    add_column :analyses, :co2, :float
    add_column :analyses, :water, :float
    add_column :analyses, :global_score, :float
    add_column :analyses, :garment_size, :string
  end
end
