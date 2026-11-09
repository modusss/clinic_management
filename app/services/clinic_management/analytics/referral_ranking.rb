module ClinicManagement
  module Analytics
    # Ranks captadores by appointment records within the same analytics period.
    # ESSENTIAL: Count all booking records, including rescheduled appointments,
    # by the service date (not when the invitation was initially created).
    # The optional region filter applies; the selected captador never filters
    # its own dropdown, so users can compare all available captadores.
    class ReferralRanking
      def initialize(start_date:, end_date:, service_location_id:, region_id: nil)
        @start_date = start_date
        @end_date = end_date
        @service_location_id = service_location_id
        @region_id = region_id
      end

      # @param referrals [Array<Array(String, Integer)>] name and ID from Referral
      # @return [Array<Hash>] ordered with highest appointment count first
      def call(referrals:)
        services = Service.for_location(@service_location_id)
                          .where(date: @start_date..@end_date, canceled: [nil, false])
        appointments = Appointment.joins(:invitation)
                                  .where(service_id: services.select(:id))
        if @region_id
          appointments = appointments.where(clinic_management_invitations: { region_id: @region_id })
        end
        counts = appointments.group("clinic_management_invitations.referral_id").count
        rank(referrals, counts)
      end

      # Stable tie-breaking: most markings, then name (case-insensitive).
      def rank(referrals, counts)
        referrals.map do |name, id|
          { name: name, id: id, count: counts.fetch(id, 0) }
        end.sort_by { |row| [-row[:count], row[:name].to_s.downcase, row[:id]] }
      end
    end
  end
end
