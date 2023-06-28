class AddMessagesSentToAppointments < ActiveRecord::Migration[7.0]
  def change
    add_column :clinic_management_appointments, :messages_sent, :text, array: true, default: []
  end
end
