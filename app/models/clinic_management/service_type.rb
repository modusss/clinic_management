module ClinicManagement
    class ServiceType < ApplicationRecord
        has_many :services, dependent: :nullify
        has_many :lead_messages, dependent: :nullify

        # Scope para filtrar service types não removidos
        scope :active, -> { where(removed: false) }
        scope :ordered, -> { order(:name) }
    end
end