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

    # Efficient version for a paginated list. Existing reservations keep their
    # created_at; no reservation belonging to another user is touched.
    def self.register_views(lead_ids, user_id, context: 'absent', duration_hours: 3)
      ids = Array(lead_ids).compact.uniq
      return if ids.empty?

      now = Time.current
      scope = where(lead_id: ids, user_id: user_id, page_context: context)
      existing_ids = scope.distinct.pluck(:lead_id)
      scope.update_all(viewed_at: now, expires_at: now + duration_hours.hours, updated_at: now) if existing_ids.any?

      missing_ids = ids - existing_ids
      return if missing_ids.empty?

      insert_all(missing_ids.map do |lead_id|
        { lead_id: lead_id, user_id: user_id, page_context: context,
          viewed_at: now, expires_at: now + duration_hours.hours,
          created_at: now, updated_at: now }
      end)
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
