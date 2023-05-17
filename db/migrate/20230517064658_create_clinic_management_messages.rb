class CreateClinicManagementMessages < ActiveRecord::Migration[7.0]
  def change
    create_table :clinic_management_messages do |t|
      t.string :name, null: false
      t.text :text, null: false
      t.timestamps
    end
  end
end
