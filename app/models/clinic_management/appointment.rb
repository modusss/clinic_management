module ClinicManagement
  class Appointment < ApplicationRecord
    belongs_to :lead
    belongs_to :service
    belongs_to :invitation, required: true
    belongs_to :registered_by_user, class_name: 'User', optional: true
    has_one :prescription
    
    # Relacionamentos para controle de remarcação
    belongs_to :recapture_by_user, class_name: 'User', optional: true
    belongs_to :recapture_audited_by, class_name: 'User', optional: true
    has_many_attached :recapture_screenshots
    
    # Validações para remarcação com esforço ativo
    validates :recapture_actions, presence: true, if: -> { recapture_origin == 'active_effort' }
    validate :at_least_one_action_selected, if: -> { recapture_origin == 'active_effort' }
    validate :screenshots_required_for_commission, if: -> { recapture_origin == 'active_effort' }
    
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
    
    # Verifica se é remarcação (existe appointment anterior remarcado do mesmo lead)
    def is_reschedule?
      return false unless lead_id.present?
      
      ClinicManagement::Appointment.where(lead_id: lead_id)
                                   .where(status: 'remarcado')
                                   .where('created_at < ?', created_at || Time.current)
                                   .exists?
    end
    
    # Retorna o appointment anterior que foi remarcado
    def previous_appointment
      return nil unless lead_id.present?
      
      ClinicManagement::Appointment.where(lead_id: lead_id)
                                   .where(status: 'remarcado')
                                   .where('created_at < ?', created_at || Time.current)
                                   .order(created_at: :desc)
                                   .first
    end

    private

    def set_registered_by_user_fallback
      # Fallback para "Sistema" quando não há usuário definido
      write_attribute(:registered_by_user, "Sistema")
    end
    
    def at_least_one_action_selected
      if recapture_actions.blank? || recapture_actions.reject(&:blank?).empty?
        errors.add(:recapture_actions, "deve ter pelo menos uma ação selecionada")
      end
    end
    
    def screenshots_required_for_commission
      if recapture_screenshots.blank? || !recapture_screenshots.attached?
        errors.add(:recapture_screenshots, "são obrigatórios para comissão por esforço ativo")
      end
    end
  end
end