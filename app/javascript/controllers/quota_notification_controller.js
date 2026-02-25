import { Controller } from "@hotwired/stimulus"

// Persist "don't show again" for quota exceeded sidebar notification.
// Key: quotaNotificationDismissed_<account_id>
export default class extends Controller {
  static values = { accountId: String }

  connect() {
    const key = this.storageKey
    if (localStorage.getItem(key) === "true") {
      this.element.classList.add("hidden")
    }
  }

  dismiss(event) {
    if (event) event.preventDefault()
    const key = this.storageKey
    localStorage.setItem(key, "true")
    this.element.classList.add("hidden")
  }

  get storageKey() {
    return `quotaNotificationDismissed_${this.accountIdValue || "default"}`
  }
}
