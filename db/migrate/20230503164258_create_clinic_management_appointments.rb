class CreateClinicManagementAppointments < ActiveRecord::Migration[7.0]
  def change
    create_table :clinic_management_appointments do |t|
      t.boolean :attendance
      t.string :status
      # t.references :lead, null: false, foreign_key: {to_table: :clinic_management_leads}
      # t.references :service, null: false, foreign_key: {to_table: :clinic_management_services}

      t.timestamps
    end

    add_reference :clinic_management_appointments, :lead, null: false, foreign_key: { to_table: :clinic_management_leads }
    add_reference :clinic_management_appointments, :service, null: false, foreign_key: { to_table: :clinic_management_services }

  end
end
