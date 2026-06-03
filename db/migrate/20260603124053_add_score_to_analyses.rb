class AddScoreToAnalyses < ActiveRecord::Migration[8.1]
  def change
    add_column :analyses, :score, :integer
  end
end
