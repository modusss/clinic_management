class AddReferralCodeToA < ActiveRecord::Migration[7.0]
  def change
    add_column :clinic_management_appointments, :referral_code, :string
  end
end
