import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["panel", "content", "toggleBtn", "chevron"]

  connect() {
    this.open = false
  }

  toggle(event) {
    // Prevent toggle if clicking on regenerate link
    if (event && event.target.closest('a')) {
      return
    }

    this.open = !this.open

    // Toggle content visibility
    if (this.hasContentTarget) {
      if (this.open) {
        this.contentTarget.classList.remove("hidden")
      } else {
        this.contentTarget.classList.add("hidden")
      }
    }

    // Rotate all chevrons
    this.chevronTargets.forEach(chevron => {
      if (this.open) {
        chevron.classList.add("rotate-180")
      } else {
        chevron.classList.remove("rotate-180")
      }
    })

    // Scroll panel into view when opening
    if (this.open && this.hasPanelTarget) {
      setTimeout(() => {
        this.panelTarget.scrollIntoView({ behavior: "smooth", block: "nearest" })
      }, 100)
    }
  }
}
