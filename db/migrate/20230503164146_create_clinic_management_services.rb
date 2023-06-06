class CreateClinicManagementServices < ActiveRecord::Migration[7.0]
  def change
    create_table :clinic_management_services do |t|
      t.integer :weekday
      t.datetime :start_time
      t.datetime :end_time
      t.datetime :date
      # t.references :time_slot, null: false, foreign_key: {to_table: :clinic_management_time_slots}

      t.timestamps
    end

    add_reference :clinic_management_services, :time_slot, null: false, foreign_key: { to_table: :clinic_management_time_slots }

  end
end
