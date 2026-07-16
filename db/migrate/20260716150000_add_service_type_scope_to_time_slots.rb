class AddServiceTypeScopeToTimeSlots < ActiveRecord::Migration[7.0]
  def change
    add_column :clinic_management_time_slots, :all_service_types, :boolean, null: false, default: true

    create_table :clinic_management_time_slot_service_types do |t|
      t.references :time_slot,
                   null: false,
                   foreign_key: { to_table: :clinic_management_time_slots },
                   index: false
      t.references :service_type,
                   null: false,
                   foreign_key: { to_table: :clinic_management_service_types },
                   index: false
      t.timestamps
    end

    add_index :clinic_management_time_slot_service_types,
              [:time_slot_id, :service_type_id],
              unique: true,
              name: "idx_cm_time_slot_service_types_unique"
  end
end
