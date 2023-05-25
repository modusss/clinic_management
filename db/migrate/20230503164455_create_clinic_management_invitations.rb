class CreateClinicManagementInvitations < ActiveRecord::Migration[7.0]
  def change
    create_table :clinic_management_invitations do |t|
      t.string :patient_name
      t.string :notes
      # t.references :lead, null: false, foreign_key: {to_table: :clinic_management_leads}
      # t.references :referral, null: false, foreign_key: {to_table: :clinic_management_referrals}
      # t.references :region, null: false, foreign_key: {to_table: :clinic_management_regions}
      # t.references :appointment, null: false, foreign_key: {to_table: :clinic_management_appointments}

      t.timestamps
    end
    add_reference :clinic_management_invitations, :lead, null: false, foreign_key: { to_table: :clinic_management_leads }
    # add_reference :clinic_management_invitations, :referral, null: false, foreign_key: { to_table: :referrals }
    add_reference :clinic_management_invitations, :region, null: false, foreign_key: { to_table: :clinic_management_regions }
    add_reference :clinic_management_invitations, :appointment, null: false, foreign_key: { to_table: :clinic_management_appointments }
  end
end
