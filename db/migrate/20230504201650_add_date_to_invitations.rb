class AddDateToInvitations < ActiveRecord::Migration[7.0]
  def change
    add_column :clinic_management_invitations, :date, :date
  end
end
