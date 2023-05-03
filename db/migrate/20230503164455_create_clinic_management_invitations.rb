class CreateClinicManagementInvitations < ActiveRecord::Migration[7.0]
  def change
    create_table :clinic_management_invitations do |t|
      t.string :patient_name
      t.string :notes
      t.references :lead, null: false, foreign_key: true
      t.references :referral, null: false, foreign_key: true
      t.references :region, null: false, foreign_key: true
      t.references :appointment, null: false, foreign_key: true

      t.timestamps
    end
  end
end
