module ClinicManagement
  class Appointment < ApplicationRecord
    belongs_to :lead
    belongs_to :service
    has_one :invitation, dependent: :destroy
  end
end
