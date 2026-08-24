# frozen_string_literal: true

class CreateClinicManagementLpvozIntegration < ActiveRecord::Migration[7.0]
  def change
    create_table :clinic_management_lpvoz_connections do |t|
      t.references :account, null: false, foreign_key: true, index: false
      t.string :status, null: false, default: "pending"
      t.string :installation_public_id
      t.string :lpvoz_base_url
      t.string :agent_key, null: false, default: "pacientes-ausentes"
      t.text :shared_secret
      t.jsonb :permissions, null: false, default: []
      t.string :pairing_code_digest
      t.datetime :pairing_expires_at
      t.datetime :pairing_used_at
      t.datetime :connected_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :clinic_management_lpvoz_connections, :account_id, unique: true
    add_index :clinic_management_lpvoz_connections, :installation_public_id, unique: true,
              where: "installation_public_id IS NOT NULL",
              name: "idx_cm_lpvoz_connections_installation"
    add_index :clinic_management_lpvoz_connections, :pairing_code_digest,
              where: "pairing_code_digest IS NOT NULL",
              name: "idx_cm_lpvoz_connections_pairing"

    create_table :clinic_management_lpvoz_operations do |t|
      t.references :account, null: false, foreign_key: true
      t.references :lpvoz_connection, null: false,
                   foreign_key: { to_table: :clinic_management_lpvoz_connections },
                   index: { name: "idx_cm_lpvoz_operations_connection" }
      t.references :lead, null: false,
                   foreign_key: { to_table: :clinic_management_leads },
                   index: { name: "idx_cm_lpvoz_operations_lead" }
      t.references :appointment, null: false,
                   foreign_key: { to_table: :clinic_management_appointments },
                   index: { name: "idx_cm_lpvoz_operations_appointment" }
      t.string :public_id, null: false
      t.string :voice_operation_id
      t.string :idempotency_key, null: false
      t.string :status, null: false, default: "queued"
      t.jsonb :result, null: false, default: {}
      t.text :last_error
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :clinic_management_lpvoz_operations, :public_id, unique: true
    add_index :clinic_management_lpvoz_operations, :voice_operation_id, unique: true,
              where: "voice_operation_id IS NOT NULL",
              name: "idx_cm_lpvoz_operations_voice_operation"
    add_index :clinic_management_lpvoz_operations, [:account_id, :idempotency_key], unique: true,
              name: "idx_cm_lpvoz_operations_idempotency"
    add_index :clinic_management_lpvoz_operations, [:account_id, :lead_id, :created_at],
              name: "idx_cm_lpvoz_operations_patient_state"

    create_table :clinic_management_lpvoz_events do |t|
      t.references :account, null: false, foreign_key: true
      t.references :lpvoz_connection, null: false,
                   foreign_key: { to_table: :clinic_management_lpvoz_connections },
                   index: { name: "idx_cm_lpvoz_events_connection" }
      t.references :lpvoz_operation, null: false,
                   foreign_key: { to_table: :clinic_management_lpvoz_operations },
                   index: { name: "idx_cm_lpvoz_events_operation" }
      t.string :event_id, null: false
      t.string :event_type, null: false
      t.string :status, null: false, default: "pending"
      t.jsonb :payload, null: false, default: {}
      t.text :last_error
      t.datetime :processed_at
      t.timestamps
    end
    add_index :clinic_management_lpvoz_events, [:lpvoz_connection_id, :event_id], unique: true,
              name: "idx_cm_lpvoz_events_idempotency"
    add_index :clinic_management_lpvoz_events, [:status, :created_at],
              name: "idx_cm_lpvoz_events_processing"
  end
end
