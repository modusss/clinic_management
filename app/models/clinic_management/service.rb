module ClinicManagement
  class Service < ApplicationRecord
    has_many :appointments, dependent: :destroy
    belongs_to :service_type, optional: true
  end
end
