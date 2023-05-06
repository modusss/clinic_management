module ClinicManagement
  class Invitation < ApplicationRecord
    belongs_to :lead
    belongs_to :referral
    belongs_to :region
    belongs_to :appointment
    has_one :invitation, dependent: :destroy
    has_one :appointment, dependent: :destroy
    
    accepts_nested_attributes_for :lead
    accepts_nested_attributes_for :appointment
    
  end
end
