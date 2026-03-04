module ClinicManagement
  class Service < ApplicationRecord
    has_many :appointments, dependent: :destroy
    belongs_to :service_type, optional: true
    belongs_to :service_location, optional: true, class_name: "ClinicManagement::ServiceLocation"

    # Adicione este escopo para buscar serviços futuros
    scope :upcoming, -> { where("date >= ?", Date.today).where(canceled: [false, nil]) }

    # Scope for filtering by service_location_id (nil = internal)
    scope :for_location, ->(location_id) { where(service_location_id: location_id) }
  end
end
