module ClinicManagement
  class Lead < ApplicationRecord
    has_many :invitations
    has_many :appointments, through: :invitations
    has_many :appointments
    has_many :conversions
    
    validates :phone, format: { with: /\A\d{10,11}\z/, message: "deve ter 10 ou 11 dígitos" }, allow_blank: true

  end
end
