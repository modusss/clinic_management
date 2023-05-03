module ClinicManagement
  class Service < ApplicationRecord
    belongs_to :time_slot
  end
end
