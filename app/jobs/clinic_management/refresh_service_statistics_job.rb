module ClinicManagement
  # ESSENTIAL: Recomputes ServiceStatistic for one past service (non-blocking via GoodJob).
  class RefreshServiceStatisticsJob < ApplicationJob
    queue_as :default

    # @param service_id [Integer]
    def perform(service_id)
      service = ClinicManagement::Service.find_by(id: service_id)
      return unless service

      ServiceStatistics::Refresher.call(service)
    end
  end
end
