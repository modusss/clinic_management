class CreateConversion < ActiveRecord::Migration[7.0]
  def change
    create_table :clinic_management_conversions do |t|
      t.references :lead, null: false, foreign_key: true
      t.references :customers, null: false, foreign_key: true
      t.timestamps
    end
  end
end
