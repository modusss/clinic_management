module ClinicManagement
  class Service < ApplicationRecord
    has_many :appointments, dependent: :destroy
  end
end
