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

ActiveRecord::Schema[7.0].define(version: 2026_08_27_130000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "clinic_management_appointments", force: :cascade do |t|
    t.boolean "attendance"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "lead_id", null: false
    t.bigint "service_id", null: false
    t.bigint "invitation_id", null: false
    t.index ["invitation_id"], name: "index_clinic_management_appointments_on_invitation_id"
    t.index ["lead_id"], name: "index_clinic_management_appointments_on_lead_id"
    t.index ["service_id"], name: "index_clinic_management_appointments_on_service_id"
  end

  create_table "clinic_management_conversions", force: :cascade do |t|
    t.bigint "lead_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["lead_id"], name: "index_clinic_management_conversions_on_lead_id"
  end

  create_table "clinic_management_invitations", force: :cascade do |t|
    t.string "patient_name"
    t.string "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "lead_id", null: false
    t.bigint "region_id", null: false
    t.date "date"
    t.index ["lead_id"], name: "index_clinic_management_invitations_on_lead_id"
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
    t.integer "last_appointment_id"
    t.index ["last_appointment_id"], name: "index_clinic_management_leads_on_last_appointment_id"
  end

  create_table "clinic_management_lpvoz_call_programs", force: :cascade do |t|
    t.bigint "account_id", null: false
    t.bigint "lpvoz_connection_id", null: false
    t.bigint "created_by_id"
    t.string "name", null: false
    t.string "agent_key", null: false
    t.string "status", default: "draft", null: false
    t.string "time_zone", default: "America/Bahia", null: false
    t.jsonb "weekdays", default: [1, 2, 3, 4, 5], null: false
    t.jsonb "time_windows", default: [{"end"=>"12:00", "start"=>"08:00"}, {"end"=>"17:00", "start"=>"13:00"}], null: false
    t.jsonb "filters", default: {}, null: false
    t.integer "daily_limit", default: 100, null: false
    t.datetime "activated_at"
    t.datetime "paused_at"
    t.datetime "last_dispatched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "status"], name: "idx_cm_lpvoz_programs_account_status"
    t.index ["account_id"], name: "index_clinic_management_lpvoz_call_programs_on_account_id"
    t.index ["created_by_id"], name: "index_clinic_management_lpvoz_call_programs_on_created_by_id"
    t.index ["lpvoz_connection_id"], name: "idx_cm_lpvoz_programs_connection"
  end

  create_table "clinic_management_regions", force: :cascade do |t|
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "clinic_management_services", force: :cascade do |t|
    t.integer "weekday"
    t.time "start_time"
    t.time "end_time"
    t.date "date"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "clinic_management_time_slots", force: :cascade do |t|
    t.integer "weekday"
    t.time "start_time"
    t.time "end_time"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "clinic_management_appointments", "clinic_management_invitations", column: "invitation_id"
  add_foreign_key "clinic_management_appointments", "clinic_management_leads", column: "lead_id"
  add_foreign_key "clinic_management_appointments", "clinic_management_services", column: "service_id"
  add_foreign_key "clinic_management_conversions", "clinic_management_leads", column: "lead_id"
  add_foreign_key "clinic_management_invitations", "clinic_management_leads", column: "lead_id"
  add_foreign_key "clinic_management_invitations", "clinic_management_regions", column: "region_id"
end
