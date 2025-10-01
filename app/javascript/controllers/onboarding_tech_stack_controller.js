import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["option", "message"]

  connect() {
    this.updateSelection()
  }

  select(event) {
    const selectedOption = event.target.closest(".tech-stack-option")

    this.optionTargets.forEach(option => option.classList.remove("selected"))
    selectedOption?.classList.add("selected")
    this.toggleMessage(event.target.value)
  }

  updateSelection() {
    const checkedRadio = this.element.querySelector("input[type='radio']:checked")
    if (checkedRadio) {
      const option = checkedRadio.closest(".tech-stack-option")
      option?.classList.add("selected")
      this.toggleMessage(checkedRadio.value)
    } else {
      this.toggleMessage(null)
    }
  }

  toggleMessage(value) {
    if (!this.hasMessageTarget) return

    const shouldWarn = value && value !== "rails"
    this.messageTarget.classList.toggle("hidden", !shouldWarn)
  }
}

