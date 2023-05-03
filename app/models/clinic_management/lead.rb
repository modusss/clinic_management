module ClinicManagement
  class Lead < ApplicationRecord
    has_many :invitations
    has_many :appointments, through: :invitations
    has_many :appointments
    has_many :conversions
  end
end
