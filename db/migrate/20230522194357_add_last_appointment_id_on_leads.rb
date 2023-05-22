class AddLastAppointmentIdOnLeads < ActiveRecord::Migration[7.0]
  def change
    add_column :clinic_management_leads, :last_appointment_id, :integer
    add_index :clinic_management_leads, :last_appointment_id
  end
end
