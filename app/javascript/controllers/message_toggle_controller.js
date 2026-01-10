import { Controller } from "@hotwired/stimulus"

// Simple controller for toggling between short/full message display
export default class extends Controller {
  static targets = ["short", "full"]

  toggle() {
    if (this.hasShortTarget && this.hasFullTarget) {
      this.shortTarget.classList.toggle("hidden")
      this.fullTarget.classList.toggle("hidden")
    }
  }
}

