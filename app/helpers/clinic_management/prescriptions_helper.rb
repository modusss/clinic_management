module ClinicManagement
  module PrescriptionsHelper

    def collection_for_sphere
      (-20..20).step(0.25).map { |x| x.round(2) }
    end

    def collection_for_cylinder
      (-10..10).step(0.25).map { |x| x.round(2) }
    end

    def collection_for_axis
      (0..180).to_a
    end

    def collection_for_add
      (0..3).step(0.25).map { |x| x.round(2) }
    end

  end
end
