import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]

  connect() {
    this.close = this.close.bind(this)
    this.closeFromEvent = this.closeFromEvent.bind(this)
    document.addEventListener("dropdown:open", this.closeFromEvent)
  }

  toggle(event) {
    event.preventDefault()

    if (this.menuTarget.classList.contains("hidden")) {
      this.open(event)
    } else {
      this.close()
    }
  }

  open(event) {
    // Close all other dropdowns first
    document.dispatchEvent(new CustomEvent("dropdown:open", { detail: { controller: this } }))

    // Position the menu using fixed positioning relative to the button
    const button = event.currentTarget
    const rect = button.getBoundingClientRect()

    this.menuTarget.style.position = 'fixed'
    this.menuTarget.style.top = `${rect.bottom + 4}px`
    this.menuTarget.style.left = `${rect.left}px`

    this.menuTarget.classList.remove("hidden")
    document.addEventListener("click", this.close)
    window.addEventListener("scroll", this.close, true)
  }

  close(event) {
    if (!event || !this.element.contains(event.target)) {
      this.menuTarget.classList.add("hidden")
      document.removeEventListener("click", this.close)
      window.removeEventListener("scroll", this.close, true)
    }
  }

  // Close this dropdown when another one opens
  closeFromEvent(event) {
    if (event.detail.controller !== this) {
      this.menuTarget.classList.add("hidden")
      document.removeEventListener("click", this.close)
      window.removeEventListener("scroll", this.close, true)
    }
  }

  disconnect() {
    document.removeEventListener("click", this.close)
    window.removeEventListener("scroll", this.close, true)
    document.removeEventListener("dropdown:open", this.closeFromEvent)
  }
}
