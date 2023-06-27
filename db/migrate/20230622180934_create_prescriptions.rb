class CreatePrescriptions < ActiveRecord::Migration[7.0]
  def change
    create_table :clinic_management_prescriptions do |t|
      t.string :sphere_right
      t.string :sphere_left
      t.string :cylinder_right
      t.string :cylinder_left
      t.string :axis_right
      t.string :axis_left
      t.string :add_right
      t.string :add_left
      t.string :comment
      t.timestamps
    end
    
    add_reference :clinic_management_prescriptions, :appointment, null: false, foreign_key: { to_table: :clinic_management_appointments }

  end
end
