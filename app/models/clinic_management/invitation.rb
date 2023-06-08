module ClinicManagement
  class Invitation < ApplicationRecord

    after_commit :update_cache

    belongs_to :lead
    belongs_to :referral, class_name: '::Referral', optional: true
    belongs_to :region
    has_many :appointments, dependent: :destroy

    accepts_nested_attributes_for :lead
    accepts_nested_attributes_for :appointments

    validates :patient_name, presence: true

    private

    def update_cache
      # Aqui estamos supondo que CacheWarmupJob está definido no aplicativo principal
      # Você deve ajustar de acordo com sua configuração real
      ::CacheWarmupJob.perform_later(self.referral_id, "index_by_referral")
    end

  end
end
