# frozen_string_literal: true

module ClinicManagement
  module FieldTracking
    # Completes an active shift and enqueues summary metrics calculation.
    class ShiftEnder
      class Error < StandardError
        attr_reader :code

        def initialize(code, message = code)
          @code = code
          super(message)
        end
      end

      # @param shift [ClinicManagement::FieldShift]
      # @param reason [String]
      # @return [ClinicManagement::FieldShift]
      def self.call(shift:, reason: "user")
        new(shift: shift, reason: reason).call
      end

      def initialize(shift:, reason: "user")
        @shift = shift
        @reason = reason
      end

      def call
        raise Error.new("shift_not_active") unless @shift.active?

        @shift.update!(
          status: "completed",
          ended_at: Time.current,
          ended_reason: @reason
        )

        ClinicManagement::FieldTracking::ShiftSummaryJob.perform_later(@shift.id)
        @shift
      end
    end
  end
end
