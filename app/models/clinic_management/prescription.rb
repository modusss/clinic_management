module ClinicManagement
    class Prescription < ApplicationRecord

        belongs_to :appointment

        # The examination's original entry time determines its financial shift.
        # Corrections to historical prescriptions must invalidate that snapshot.
        after_commit :refresh_financial_shift, on: [:create, :update, :destroy]

        private

        def refresh_financial_shift
            return unless ServiceStatistics::Policy.retail_sales_enabled?

            service_id = appointment&.service_id
            return unless service_id

            date = ClinicManagement::Service.where(id: service_id).pick(:date)
            return unless date && date < Date.current

            ClinicManagement::RefreshServiceStatisticsJob.perform_later(service_id)
        end

    end
end
