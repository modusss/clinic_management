# frozen_string_literal: true

module ClinicManagement
  module Api
    module V1
      module Field
        module Scheduling
          # Exact-phone patient lookup within the captador's permitted lead scope.
          class PatientsController < BaseController
            def lookup
              phone = params[:phone].to_s.gsub(/\D/, "")
              if phone.blank?
                return render json: { error: "invalid_phone", message: "Informe um telefone com DDD." }, status: :unprocessable_entity
              end

              leads = scheduling_policy.lead_scope.where(phone: phone).includes(:invitations).limit(10)
              render json: {
                leads: leads.map do |lead|
                  {
                    id: lead.id,
                    responsible_name: lead.name,
                    phone: lead.phone,
                    address: lead.address,
                    patients: lead.distinct_patients
                  }
                end
              }
            end
          end
        end
      end
    end
  end
end
