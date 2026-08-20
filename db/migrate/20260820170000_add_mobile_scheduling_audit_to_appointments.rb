# frozen_string_literal: true

class AddMobileSchedulingAuditToAppointments < ActiveRecord::Migration[7.0]
  def change
    add_column :clinic_management_appointments, :mobile_request_id, :string
    add_reference :clinic_management_appointments,
                  :rescheduled_from_appointment,
                  foreign_key: { to_table: :clinic_management_appointments },
                  index: { name: "idx_cm_appointments_rescheduled_from" }
    add_index :clinic_management_appointments,
              :mobile_request_id,
              unique: true,
              where: "mobile_request_id IS NOT NULL",
              name: "idx_cm_appointments_mobile_request_unique"
  end
end
