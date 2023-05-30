module ClinicManagement
  class Lead < ApplicationRecord
    has_many :invitations
    has_many :appointments, through: :invitations
    has_many :appointments
    has_one :leads_conversion, foreign_key: 'clinic_management_lead_id'
    has_one :customer, through: :leads_conversion
    validates :phone, format: { with: /\A\d{10,11}\z/, message: "deve ter 10 ou 11 dígitos" }, allow_blank: true

  end
end
