import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "buttonText", "spinner", "icon", "waitText"]
  static values  = { url: String }

  generate(event) {
    event.preventDefault()

    // Disable button and show spinner
    this.buttonTarget.disabled = true
    this.buttonTarget.classList.add("opacity-75", "cursor-wait")
    this.buttonTarget.classList.remove("cursor-pointer")

    if (this.hasButtonTextTarget) {
      this.buttonTextTarget.textContent = "Analyzing..."
    }

    if (this.hasIconTarget) {
      this.iconTarget.classList.add("hidden")
    }

    if (this.hasSpinnerTarget) {
      this.spinnerTarget.classList.remove("hidden")
    }

    if (this.hasWaitTextTarget) {
      this.waitTextTarget.classList.remove("hidden")
    }

    // Get CSRF token
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content

    // Make async request
    fetch(this.urlValue, {
      method: "POST",
      headers: {
        "Accept": "application/json",
        "X-CSRF-Token": csrfToken,
        "X-Requested-With": "XMLHttpRequest"
      },
      credentials: "same-origin"
    })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        // Reload to show the new AI analysis panel
        window.location.reload()
      } else if (data.quota_exceeded) {
        // Quota exceeded — reload page so ERB renders the correct quota UI
        window.location.reload()
      } else {
        // Show error
        this.resetButton()
        if (this.hasWaitTextTarget) {
          this.waitTextTarget.textContent = data.message || "Failed to generate AI analysis. Please try again."
          this.waitTextTarget.classList.remove("hidden", "text-gray-500")
          this.waitTextTarget.classList.add("text-red-600")
        }
      }
    })
    .catch(error => {
      console.error("Generate AI error:", error)
      this.resetButton()
      if (this.hasWaitTextTarget) {
        this.waitTextTarget.textContent = "Something went wrong. Please try again."
        this.waitTextTarget.classList.remove("hidden", "text-gray-500")
        this.waitTextTarget.classList.add("text-red-600")
      }
    })
  }

  resetButton() {
    this.buttonTarget.disabled = false
    this.buttonTarget.classList.remove("opacity-75", "cursor-wait")
    this.buttonTarget.classList.add("cursor-pointer")

    if (this.hasButtonTextTarget) {
      this.buttonTextTarget.textContent = "Generate AI"
    }

    if (this.hasSpinnerTarget) {
      this.spinnerTarget.classList.add("hidden")
    }

    if (this.hasIconTarget) {
      this.iconTarget.classList.remove("hidden")
    }
  }
}
