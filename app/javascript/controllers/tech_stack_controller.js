import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["option", "indicator"]

  connect() {
    // Set initial selection if any
    this.updateSelection()
  }

    select(event) {
    const selectedOption = event.target.closest('.tech-stack-option')

    // Remove selection from all options
    this.element.querySelectorAll('.tech-stack-option').forEach(option => {
      option.classList.remove('selected')
    })

    // Add selection to clicked option
    selectedOption.classList.add('selected')
  }

  updateSelection() {
    // Find the checked radio button and update the UI
    const checkedRadio = this.element.querySelector('input[type="radio"]:checked')
    if (checkedRadio) {
      const option = checkedRadio.closest('.tech-stack-option')
      if (option) {
        option.classList.add('selected')
      }
    }
  }
}
