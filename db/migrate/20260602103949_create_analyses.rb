class CreateAnalyses < ActiveRecord::Migration[8.1]
  def change
    create_table :analyses do |t|
      t.references :user, null: true, foreign_key: true
      t.integer :status

      t.timestamps
    end
  end
end
