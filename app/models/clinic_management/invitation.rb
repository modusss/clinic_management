module ClinicManagement
  class Invitation < ApplicationRecord
    belongs_to :lead
    belongs_to :referral
    belongs_to :region
    has_many :appointments
    
    accepts_nested_attributes_for :lead
    accepts_nested_attributes_for :appointments
  end
end
