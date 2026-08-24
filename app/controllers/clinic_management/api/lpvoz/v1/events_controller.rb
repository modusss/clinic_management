# frozen_string_literal: true

module ClinicManagement
  module Api
    module Lpvoz
      module V1
        class EventsController < BaseController
          def create
            payload = request.request_parameters.deep_stringify_keys
            record = connection.lpvoz_operations.find_by!(public_id: payload.fetch("external_reference"))
            event = connection.lpvoz_events.find_by(event_id: payload.fetch("event_id"))
            if event
              return render_event_replay(event, payload)
            end

            event = connection.lpvoz_events.create!(event_id: payload.fetch("event_id")) do |entry|
              entry.account = connection.account
              entry.lpvoz_operation = record
              entry.event_type = payload.fetch("event_type")
              entry.payload = payload
            end
            render json: { accepted: true, duplicate: false }, status: :accepted
          rescue ActiveRecord::RecordNotUnique
            render_event_replay(connection.lpvoz_events.find_by!(event_id: payload.fetch("event_id")), payload)
          rescue KeyError, ActiveRecord::RecordNotFound => error
            render json: { error: error.message }, status: :unprocessable_entity
          end

          private

          def render_event_replay(event, payload)
            if event.payload == payload
              render json: { accepted: true, duplicate: true }, status: :accepted
            else
              render json: { error: "event_id já utilizado com outro conteúdo." }, status: :conflict
            end
          end
        end
      end
    end
  end
end
