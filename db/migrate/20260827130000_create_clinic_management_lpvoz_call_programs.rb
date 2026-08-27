# frozen_string_literal: true

class CreateClinicManagementLpvozCallPrograms < ActiveRecord::Migration[7.0]
  def change
    create_table :clinic_management_lpvoz_call_programs do |t|
      t.references :account, null: false, foreign_key: true
      t.references :lpvoz_connection, null: false,
                   foreign_key: { to_table: :clinic_management_lpvoz_connections },
                   index: { name: "idx_cm_lpvoz_programs_connection" }
      t.references :created_by, null: true, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.string :agent_key, null: false
      t.string :status, null: false, default: "draft"
      t.string :time_zone, null: false, default: "America/Bahia"
      t.jsonb :weekdays, null: false, default: [1, 2, 3, 4, 5]
      t.jsonb :time_windows, null: false,
              default: [{ "start" => "08:00", "end" => "12:00" }, { "start" => "13:00", "end" => "17:00" }]
      t.jsonb :filters, null: false, default: {}
      t.integer :daily_limit, null: false, default: 100
      t.datetime :activated_at
      t.datetime :paused_at
      t.datetime :last_dispatched_at
      t.timestamps
    end

    add_index :clinic_management_lpvoz_call_programs, [:account_id, :status],
              name: "idx_cm_lpvoz_programs_account_status"

    add_reference :clinic_management_lpvoz_operations, :lpvoz_call_program,
                  null: true,
                  foreign_key: { to_table: :clinic_management_lpvoz_call_programs },
                  index: { name: "idx_cm_lpvoz_operations_program" }
    add_column :clinic_management_lpvoz_operations, :agent_key, :string
  end
end
