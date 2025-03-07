module ClinicManagement
  class Service < ApplicationRecord
    has_many :appointments, dependent: :destroy
    belongs_to :service_type, optional: true

    # Adicione este escopo para buscar serviços futuros
    scope :upcoming, -> { where("date >= ?", Date.today).where(canceled: [false, nil]) }
  end
end
