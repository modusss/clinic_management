class CreateClinicManagementLeads < ActiveRecord::Migration[7.0]
  def change
    create_table :clinic_management_leads do |t|
      t.string :name
      t.string :phone
      t.string :address
      t.boolean :converted

      t.timestamps
    end
  end
end
