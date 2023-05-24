class ChangeTimeSlots < ActiveRecord::Migration[7.0]
  def change
    change_column :clinic_management_time_slots, :start_time, :time
    change_column :clinic_management_time_slots, :end_time, :time
  end
end
