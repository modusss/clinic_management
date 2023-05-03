class CreateClinicManagementTimeSlots < ActiveRecord::Migration[7.0]
  def change
    create_table :clinic_management_time_slots do |t|
      t.integer :weekday
      t.datetime :start_time
      t.datetime :end_time

      t.timestamps
    end
  end
end
