module ClinicManagement
  class Invitation < ApplicationRecord
    belongs_to :lead
    belongs_to :referral
    belongs_to :region
    belongs_to :appointment

    accepts_nested_attributes_for :lead

  end
end
