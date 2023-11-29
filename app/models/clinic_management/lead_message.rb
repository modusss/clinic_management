module ClinicManagement
    class LeadMessage < ApplicationRecord
      enum message_type: { confirmação: 0, remarcação: 1, lembrete: 2, outro: 3 }
    end
end
  