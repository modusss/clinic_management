class ChangeServices < ActiveRecord::Migration[7.0]
  def change
    change_column :clinic_management_services, :start_time, :time
    change_column :clinic_management_services, :end_time, :time
    change_column :clinic_management_services, :date, :date
  end
end
