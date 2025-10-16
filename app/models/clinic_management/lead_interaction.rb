module ClinicManagement
  class LeadInteraction < ApplicationRecord
    self.table_name = 'clinic_management_lead_interactions'
    
    belongs_to :lead
    belongs_to :appointment, optional: true
    belongs_to :user, class_name: '::User', optional: true
    
    validates :interaction_type, presence: true
    validates :occurred_at, presence: true
    
    enum interaction_type: {
      whatsapp_click: 'whatsapp_click',
      phone_call: 'phone_call'
    }
    
    scope :recent, -> { order(occurred_at: :desc) }
    scope :by_user, ->(user) { where(user: user) }
    scope :by_type, ->(type) { where(interaction_type: type) }
    
    # Estatísticas simples
    def self.count_by_user
      group(:user_id).count
    end
    
    def self.count_by_type
      group(:interaction_type).count
    end
  end
end 