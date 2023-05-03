module ClinicManagement
  class Invitation < ApplicationRecord
    belongs_to :lead
    belongs_to :referral
    belongs_to :region
    belongs_to :appointment
  end
end
