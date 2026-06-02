class CreateCriteria < ActiveRecord::Migration[8.1]
  def change
    create_table :criteria do |t|
      t.references :analysis, null: false, foreign_key: true
      t.string :name
      t.text :detail
      t.integer :score

      t.timestamps
    end
  end
end
