module ClinicManagement
    class LeadMessage < ApplicationRecord
      enum message_type: { confirmação: 0, 
                           remarcação: 1, 
                           lembrete: 2, 
                           recuperação_mesmo_dia: 4,
                           recuperação_dois_dias: 5,
                           recuperação_sete_dias: 6,
                           recuperação_quinze_dias: 7,
                           recuperação_dois_meses: 8,
                           outro: 3 }
      belongs_to :service_type, optional: true
    end
end
  