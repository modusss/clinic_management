module ClinicManagement
  class Invitation < ApplicationRecord
    belongs_to :lead
    belongs_to :referral, class_name: '::Referral', optional: true
    belongs_to :region
    has_many :appointments

    accepts_nested_attributes_for :lead
    accepts_nested_attributes_for :appointments

    validates :patient_name, presence: true

  end
end
