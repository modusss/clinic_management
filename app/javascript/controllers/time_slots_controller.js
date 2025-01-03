import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  toggleDates(event) {
    const timeSlotId = event.target.dataset.timeSlotId
    const datesContainer = document.getElementById(`dates-${timeSlotId}`)
    
    if (event.target.checked) {
      datesContainer.classList.remove('hidden')
    } else {
      datesContainer.classList.add('hidden')
      // Desmarca todas as datas quando o horário é desmarcado
      datesContainer.querySelectorAll('input[type="checkbox"]').forEach(checkbox => {
        checkbox.checked = false
      })
    }
  }
} 