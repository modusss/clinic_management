module ClinicManagement
  class LeadInteraction < ApplicationRecord
    self.table_name = 'clinic_management_lead_interactions'
    
    belongs_to :lead
    belongs_to :appointment, optional: true, inverse_of: :lead_interactions
    belongs_to :user, class_name: '::User', optional: true
    
    validates :interaction_type, presence: true
    validates :occurred_at, presence: true
    
    # ESSENTIAL: phone_call = dial attempt on "Ligar"; phone_call_answered = user confirmed pickup on "Sim".
    enum interaction_type: {
      whatsapp_click: 'whatsapp_click',
      phone_call: 'phone_call',
      phone_call_answered: 'phone_call_answered'
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