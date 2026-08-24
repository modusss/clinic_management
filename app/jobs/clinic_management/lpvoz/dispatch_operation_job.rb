# frozen_string_literal: true

module ClinicManagement
  module Lpvoz
    class DispatchOperationJob < ApplicationJob
      queue_as :default

      def perform(operation_id)
        operation = ClinicManagement::LpvozOperation.find(operation_id)
        return if operation.terminal? || operation.voice_operation_id.present?

        operation.update!(status: :dispatching, started_at: operation.started_at || Time.current)
        response = ClinicManagement::Lpvoz::Client.new(connection: operation.lpvoz_connection).create_operation(operation)
        operation.update!(voice_operation_id: response.fetch("id"), status: normalize_status(response["status"]))
      rescue ClinicManagement::Lpvoz::Client::RequestFailed, KeyError => error
        operation&.update!(status: :failed, last_error: error.message, completed_at: Time.current)
      end

      private

      def normalize_status(value)
        value.to_s.in?(%w[accepted scheduled dispatching]) ? :accepted : :dispatching
      end
    end
  end
end
