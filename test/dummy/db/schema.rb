# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.0].define(version: 2023_05_17_203815) do
  create_table "clinic_management_appointments", force: :cascade do |t|
    t.boolean "attendance"
    t.string "status"
    t.integer "lead_id", null: false
    t.integer "service_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lead_id"], name: "index_clinic_management_appointments_on_lead_id"
    t.index ["service_id"], name: "index_clinic_management_appointments_on_service_id"
  end

  create_table "clinic_management_conversions", force: :cascade do |t|
    t.integer "lead_id", null: false
    t.integer "customers_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customers_id"], name: "index_clinic_management_conversions_on_customers_id"
    t.index ["lead_id"], name: "index_clinic_management_conversions_on_lead_id"
  end

  create_table "clinic_management_invitations", force: :cascade do |t|
    t.string "patient_name"
    t.string "notes"
    t.integer "lead_id", null: false
    t.integer "referral_id", null: false
    t.integer "region_id", null: false
    t.integer "appointment_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "date"
    t.index ["appointment_id"], name: "index_clinic_management_invitations_on_appointment_id"
    t.index ["lead_id"], name: "index_clinic_management_invitations_on_lead_id"
    t.index ["referral_id"], name: "index_clinic_management_invitations_on_referral_id"
    t.index ["region_id"], name: "index_clinic_management_invitations_on_region_id"
  end

  create_table "clinic_management_lead_messages", force: :cascade do |t|
    t.string "name", null: false
    t.text "text", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "clinic_management_leads", force: :cascade do |t|
    t.string "name"
    t.string "phone"
    t.string "address"
    t.boolean "converted"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "clinic_management_regions", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "clinic_management_services", force: :cascade do |t|
    t.integer "weekday"
    t.datetime "start_time"
    t.datetime "end_time"
    t.datetime "date"
    t.integer "time_slot_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["time_slot_id"], name: "index_clinic_management_services_on_time_slot_id"
  end

  create_table "clinic_management_time_slots", force: :cascade do |t|
    t.integer "weekday"
    t.datetime "start_time"
    t.datetime "end_time"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "clinic_management_appointments", "leads"
  add_foreign_key "clinic_management_appointments", "services"
  add_foreign_key "clinic_management_conversions", "customers", column: "customers_id"
  add_foreign_key "clinic_management_conversions", "leads"
  add_foreign_key "clinic_management_invitations", "appointments"
  add_foreign_key "clinic_management_invitations", "leads"
  add_foreign_key "clinic_management_invitations", "referrals"
  add_foreign_key "clinic_management_invitations", "regions"
  add_foreign_key "clinic_management_services", "time_slots"
end
