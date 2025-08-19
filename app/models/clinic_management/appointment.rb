module ClinicManagement
  class Appointment < ApplicationRecord
    belongs_to :lead
    belongs_to :service
    belongs_to :invitation, required: true
    has_one :prescription
    
    # Callback para definir o usuário atual se não foi especificado
    before_save :set_registered_by_user, if: -> { registered_by_user.blank? }

    private

    def set_registered_by_user
      # Este método será chamado pelo controlador com o current_user
      # mas podemos ter um fallback caso não seja definido
      self.registered_by_user = "Sistema"
    end
  end
end