module ClinicManagement
  class LeadPageView < ApplicationRecord
    belongs_to :lead
    belongs_to :user

    # Escopo para buscar visualizações ativas (não expiradas)
    scope :active, -> { where('expires_at > ?', Time.current) }
    
    # Escopo para buscar por contexto
    scope :for_context, ->(context) { where(page_context: context) }
    
    # Escopo para buscar por outro usuário (não o atual)
    scope :by_other_users, ->(user_id) { where.not(user_id: user_id) }

    # Método de classe para registrar visualização
    def self.register_view(lead_id, user_id, context: 'absent', duration_hours: 3)
      # Buscar ou criar registro
      view = find_or_initialize_by(
        lead_id: lead_id,
        user_id: user_id,
        page_context: context
      )
      
      view.viewed_at = Time.current
      view.expires_at = duration_hours.hours.from_now
      view.save!
      
      view
    end

    # Método de classe para limpar visualizações expiradas
    def self.cleanup_expired
      where('expires_at < ?', Time.current).delete_all
    end

    # Método de classe para obter IDs de leads bloqueados para um usuário
    def self.blocked_lead_ids_for_user(user_id, context: 'absent')
      active
        .for_context(context)
        .by_other_users(user_id)
        .pluck(:lead_id)
        .uniq
    end
  end
end

