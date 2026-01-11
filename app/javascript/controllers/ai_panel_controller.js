import { Controller } from "@hotwired/stimulus"

// Controller for the expandable AI Analysis panel
export default class extends Controller {
  static targets = ["panel", "toggleBtn", "chevron"]
  static values = { open: { type: Boolean, default: false } }

  connect() {
    this.updateState()
  }

  toggle() {
    this.openValue = !this.openValue
    this.updateState()
  }

  close() {
    this.openValue = false
    this.updateState()
  }

  open() {
    this.openValue = true
    this.updateState()
  }

  updateState() {
    if (this.hasPanelTarget) {
      if (this.openValue) {
        this.panelTarget.classList.remove("hidden")
        // Smooth animation
        this.panelTarget.style.opacity = "0"
        this.panelTarget.style.transform = "translateY(-10px)"
        requestAnimationFrame(() => {
          this.panelTarget.style.transition = "opacity 0.2s ease, transform 0.2s ease"
          this.panelTarget.style.opacity = "1"
          this.panelTarget.style.transform = "translateY(0)"
        })
      } else {
        this.panelTarget.style.opacity = "0"
        this.panelTarget.style.transform = "translateY(-10px)"
        setTimeout(() => {
          this.panelTarget.classList.add("hidden")
        }, 200)
      }
    }

    if (this.hasChevronTarget) {
      this.chevronTarget.classList.toggle("rotate-180", this.openValue)
    }
  }
}

