module ClinicManagement
  # Educational page used by doctors to explain refractive errors to patients.
  # ESSENTIAL: Access is restricted to doctor memberships inside clinic_management.
  class EyeEducationsController < ApplicationController
    skip_before_action :redirect_doctor_users, only: [:show]
    before_action :ensure_doctor_user!

    def show
      @eye_conditions = eye_conditions_data
    end

    private

    def ensure_doctor_user!
      return if doctor_user?

      redirect_to clinic_management.index_today_path, alert: "Acesso disponível apenas para doutores."
    end

    # Returns the educational tabs rendered in the doctor page.
    # ESSENTIAL: Keep keys stable because the Stimulus tab controller depends on tab ids.
    def eye_conditions_data
      [
        {
          key: "miopia",
          title: "Miopia",
          subtitle: "Dificuldade para enxergar de longe.",
          image_path: "clinic_management/miopia.jpg",
          description: "Na miopia, os raios de luz focam antes da retina. O paciente tende a aproximar objetos para ganhar nitidez e pode relatar desconforto em atividades que exigem visão de longe."
        },
        {
          key: "astigmatismo",
          title: "Astigmatismo",
          subtitle: "Imagem borrada e distorcida em várias distâncias.",
          image_path: "clinic_management/astigmatismo.jpg",
          description: "No astigmatismo, a curvatura da córnea (ou do cristalino) é irregular. A luz foca em mais de um ponto, causando sombras e perda de definição."
        },
        {
          key: "hipermetropia",
          title: "Hipermetropia",
          subtitle: "Maior esforço para foco de perto.",
          image_path: "clinic_management/hipermetropia.jpg",
          description: "Na hipermetropia, os raios de luz tendem a focar depois da retina. O esforço acomodativo pode gerar cansaço visual, especialmente em leitura e uso de telas."
        },
        {
          key: "presbiopia",
          title: "Presbiopia",
          subtitle: "Perda natural do foco para perto com a idade.",
          image_path: "clinic_management/presbiopia.jpg",
          description: "A presbiopia está relacionada à redução da flexibilidade do cristalino ao longo do tempo. É comum o paciente afastar o texto para conseguir ler."
        }
      ]
    end
  end
end
