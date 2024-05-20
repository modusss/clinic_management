module ClinicManagement
    class ServiceType < ApplicationRecord
        has_many :services, dependent: :nullify
        has_many :lead_messages, dependent: :nullify
    end
end