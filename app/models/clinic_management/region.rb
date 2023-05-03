module ClinicManagement
  class Region < ApplicationRecord
    has_many :invitations
  end
end
