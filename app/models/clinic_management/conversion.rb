module ClinicManagement
    class Conversion < ApplicationRecord
      belongs_to :lead
      belongs_to :customers
    end
  end
  