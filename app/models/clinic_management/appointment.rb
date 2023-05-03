module ClinicManagement
  class Appointment < ApplicationRecord
    belongs_to :lead
    belongs_to :service
  end
end
