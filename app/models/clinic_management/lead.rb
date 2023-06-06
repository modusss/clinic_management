module ClinicManagement
  class Lead < ApplicationRecord
    has_many :invitations, dependent: :destroy
    has_many :appointments, through: :invitations
    has_many :appointments, dependent: :destroy
    has_one :leads_conversion, foreign_key: 'clinic_management_lead_id'
    has_one :customer, through: :leads_conversion
    validates :phone, format: { with: /\A\d{10,11}\z/, message: "deve ter 10 ou 11 dígitos" }, allow_blank: true

    before_destroy :destroy_appointments

    def destroy_appointments
      appointments.destroy_all
    end

  end
end
