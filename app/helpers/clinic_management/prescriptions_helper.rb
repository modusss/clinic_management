module ClinicManagement
  module PrescriptionsHelper

    def translate_type(type)
      case type
      when 'sphere'
        'Esférico'
      when 'cylinder'
        'Cilindro'
      when 'axis'
        'Eixo'
      when 'add'
        'Adição'
      else
        type
      end
    end

    def translate_side(side)
      case side
      when 'right'
        'Direito'
      when 'left'
        'Esquerdo'
      else
        side
      end
    end

    def collection_for_sphere
      (-25..25).step(0.25).map { |x| x.positive? ? "+#{x.round(2)}" : x.round(2).to_s }
    end
    
    def collection_for_cylinder
      (-10..0).step(0.25).map { |x| x.round(2) }
    end

    def collection_for_axis
      (0..180).to_a
    end

    def collection_for_add
      (0..3).step(0.25).map { |x| x.positive? ? "+#{x.round(2)}" : x.round(2).to_s }

    end

  end
end
