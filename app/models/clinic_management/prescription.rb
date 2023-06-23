module ClinicManagement
    class Prescription < ApplicationRecord

        belongs_to :appointment

    end
end