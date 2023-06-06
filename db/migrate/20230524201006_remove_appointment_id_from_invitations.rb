class RemoveAppointmentIdFromInvitations < ActiveRecord::Migration[7.0]
  def change
    remove_column :clinic_management_invitations, :appointment_id, index: true, foreign_key: true
  end  
end
