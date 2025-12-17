import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["master", "channel"]

  toggle() {
    if (this.masterTarget.checked) {
      this.channelTargets.forEach((checkbox) => {
        if (!checkbox.disabled) {
          checkbox.checked = true
        }
      })
    }
  }
}
