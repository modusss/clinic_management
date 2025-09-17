module ClinicManagement
  class Appointment < ApplicationRecord
    belongs_to :lead
    belongs_to :service
    belongs_to :invitation, required: true
    belongs_to :registered_by_user, class_name: 'User', optional: true
    has_one :prescription
    
    # Callback para definir o usuário atual se não foi especificado
    before_save :set_registered_by_user_fallback, if: -> { registered_by_user_id.blank? && read_attribute(:registered_by_user).blank? }

    # Método helper para exibir o nome do usuário que registrou
    def registered_by_user_name
      if registered_by_user_id.present?
        User.find_by(id: registered_by_user_id)&.name || "Usuário não encontrado"
      else
        read_attribute(:registered_by_user).presence || "Sistema"
      end
    end

    private

    def set_registered_by_user_fallback
      # Fallback para "Sistema" quando não há usuário definido
      write_attribute(:registered_by_user, "Sistema")
    end
  end
end