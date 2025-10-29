module ClinicManagement
  class CleanupLeadViewsJob < ApplicationJob
    queue_as :default

    def perform
      deleted_count = LeadPageView.cleanup_expired
      Rails.logger.info "🧹 CleanupLeadViewsJob: #{deleted_count} visualizações expiradas removidas"
    end
  end
end

