# ESSENTIAL: Pre-aggregated clinic service metrics for fast monthly/weekly owner stats.
class CreateClinicManagementServiceStatistics < ActiveRecord::Migration[7.0]
  def change
    create_table :clinic_management_service_statistics do |t|
      t.references :service,
                   null: false,
                   foreign_key: { to_table: :clinic_management_services },
                   index: { unique: true }
      t.date :service_date, null: false
      t.bigint :service_location_id

      t.integer :patients_count, null: false, default: 0
      t.integer :attended_count, null: false, default: 0
      t.integer :canceled_count, null: false, default: 0

      t.integer :sales_customers_count, null: false, default: 0
      t.decimal :sales_amount, precision: 12, scale: 2, null: false, default: 0
      t.decimal :receipts_amount, precision: 12, scale: 2, null: false, default: 0

      t.datetime :appointment_counts_computed_at
      t.datetime :sales_computed_at
      t.datetime :sales_frozen_at

      t.timestamps
    end

    add_index :clinic_management_service_statistics, :service_date, name: "idx_clinic_svc_stats_on_date"
    add_index :clinic_management_service_statistics,
              :service_location_id,
              name: "idx_clinic_svc_stats_on_location"
    add_index :clinic_management_service_statistics,
              %i[service_date service_location_id],
              name: "idx_clinic_svc_stats_on_date_location"
  end
end
