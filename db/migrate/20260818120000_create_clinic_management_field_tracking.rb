# ESSENTIAL: Field representative route tracking (shifts + GPS points + mobile auth tokens).
class CreateClinicManagementFieldTracking < ActiveRecord::Migration[7.0]
  def change
    create_table :clinic_management_field_shifts do |t|
      t.references :referral, null: false, foreign_key: { to_table: :referrals }, index: true
      t.references :user, null: false, foreign_key: true, index: true
      t.string :status, null: false, default: "active"
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.integer :points_count, null: false, default: 0
      t.integer :distance_meters
      t.integer :duration_seconds
      t.decimal :avg_speed_kmh, precision: 8, scale: 2
      t.decimal :avg_accuracy_meters, precision: 8, scale: 2
      t.jsonb :device_metadata, null: false, default: {}
      t.string :ended_reason
      t.timestamps
    end

    add_index :clinic_management_field_shifts,
              %i[referral_id status],
              name: "idx_clinic_field_shifts_referral_status"

    create_table :clinic_management_field_track_points do |t|
      t.references :field_shift,
                   null: false,
                   foreign_key: { to_table: :clinic_management_field_shifts },
                   index: { name: "idx_clinic_field_points_on_shift" }
      t.uuid :client_point_id, null: false
      t.datetime :recorded_at, null: false
      t.decimal :latitude, precision: 10, scale: 6, null: false
      t.decimal :longitude, precision: 10, scale: 6, null: false
      t.decimal :accuracy_meters, precision: 8, scale: 2
      t.decimal :speed_mps, precision: 8, scale: 3
      t.decimal :bearing, precision: 8, scale: 2
      t.timestamps
    end

    add_index :clinic_management_field_track_points,
              %i[field_shift_id recorded_at],
              name: "idx_clinic_field_points_shift_recorded"

    add_index :clinic_management_field_track_points,
              %i[field_shift_id client_point_id],
              unique: true,
              name: "idx_clinic_field_points_shift_client_id"

    create_table :clinic_management_field_mobile_tokens do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.string :token_digest, null: false
      t.string :device_label
      t.string :platform, null: false, default: "android"
      t.datetime :last_used_at
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :clinic_management_field_mobile_tokens,
              :token_digest,
              unique: true,
              name: "idx_clinic_field_mobile_tokens_digest"

    create_table :clinic_management_field_tracking_consents do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.datetime :accepted_at, null: false
      t.string :app_version
      t.string :platform, null: false, default: "android"
      t.timestamps
    end
  end
end
