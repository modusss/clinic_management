class AddDoctorNameToPrescriptions < ActiveRecord::Migration[7.0]
  def change
    add_column :clinic_management_prescriptions, :doctor_name, :string
  end
end
