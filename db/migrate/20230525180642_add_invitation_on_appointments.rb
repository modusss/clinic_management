class AddInvitationOnAppointments < ActiveRecord::Migration[7.0]
  def change
    add_reference :clinic_management_appointments, :invitation, null: false, foreign_key: { to_table: :clinic_management_invitations }
  end
end
