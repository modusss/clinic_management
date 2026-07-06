module ClinicManagement
  module AppointmentsHelper
    # ESSENTIAL: Shared cancel-column UX for lead show + service day tables — keep in sync with
    # AppointmentsController#cancel_attendance and #restore_cancel (Turbo updates same DOM ids).
    #
    # Rules:
    # - Past service date → "--"
    # - status cancelado → "cancelado" + discreet undo [×]
    # - status agendado + today/future → red Cancelar button
    def cancel_attendance_button(appointment)
      ap = appointment
      service_date = ap.service&.date

      if ap.status == "cancelado"
        return cancel_attendance_undo_label(ap)
      end

      unless ap.status == "agendado" && service_date.present? && service_date >= Date.current
        return "--"
      end

      button_to(
        "Cancelar",
        cancel_attendance_appointment_path(ap),
        method: :patch,
        remote: true,
        class: "py-2 px-4 bg-red-500 text-white rounded hover:bg-red-700"
      )
    end

    # Discreet undo control shown after cancellation; restores agendado via Turbo.
    def cancel_attendance_undo_label(appointment)
      content_tag(:span, class: "inline-flex items-center gap-1 text-sm whitespace-nowrap") do
        safe_join([
          content_tag(:span, "cancelado", class: "text-red-600 lowercase"),
          link_to(
            "×",
            restore_cancel_appointment_path(appointment),
            data: { turbo_method: :patch },
            class: "inline-flex items-center justify-center w-5 h-5 rounded text-gray-400 hover:text-gray-600 hover:bg-gray-100 text-base leading-none no-underline",
            title: "desfazer o cancelamento e tornar agendado",
            aria: { label: "desfazer o cancelamento e tornar agendado" }
          )
        ])
      end
    end
  end
end
