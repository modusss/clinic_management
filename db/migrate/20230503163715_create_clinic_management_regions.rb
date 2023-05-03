class CreateClinicManagementRegions < ActiveRecord::Migration[7.0]
  def change
    create_table :clinic_management_regions do |t|
      t.string :name

      t.timestamps
    end
  end
end
