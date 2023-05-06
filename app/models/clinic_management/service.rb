module ClinicManagement
  class Service < ApplicationRecord
    belongs_to :time_slot
    has_many :appointments, dependent: :destroy
  end
end
