class AddScheduledBookingToClinicManagement < ActiveRecord::Migration[7.0]
  def change
    add_column :clinic_management_time_slots, :booking_mode, :string, null: false, default: "arrival_order"
    add_column :clinic_management_time_slots, :interval_minutes, :integer

    add_column :clinic_management_services, :booking_mode, :string, null: false, default: "arrival_order"
    add_column :clinic_management_services, :interval_minutes, :integer

    add_column :clinic_management_appointments, :scheduled_at, :datetime
    add_column :clinic_management_appointments, :overbooked, :boolean, null: false, default: false

    add_index :clinic_management_appointments, [:service_id, :scheduled_at],
              name: "idx_clinic_appointments_service_scheduled_at"
  end
end
