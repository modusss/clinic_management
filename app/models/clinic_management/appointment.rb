module ClinicManagement
  class Appointment < ApplicationRecord
    belongs_to :lead
    belongs_to :service
    belongs_to :invitation
    has_one :prescription
  end
end