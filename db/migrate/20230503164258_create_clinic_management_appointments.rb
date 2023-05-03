class CreateClinicManagementAppointments < ActiveRecord::Migration[7.0]
  def change
    create_table :clinic_management_appointments do |t|
      t.boolean :attendance
      t.string :status
      t.references :lead, null: false, foreign_key: true
      t.references :service, null: false, foreign_key: true

      t.timestamps
    end
  end
end
