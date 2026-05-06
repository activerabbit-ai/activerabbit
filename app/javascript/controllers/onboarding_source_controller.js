import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  showSentry(event) {
    this.copyAppName("sentry_app_name_hidden")
    fetch("/onboarding/source", {
      method: "POST",
      headers: { "Accept": "text/vnd.turbo-stream.html", "X-CSRF-Token": this.csrfToken() },
      body: new URLSearchParams({ "preview": "sentry" })
    }).then(r => r.text()).then(html => Turbo.renderStreamMessage(html))
  }
  showSdk(event) {
    this.copyAppName("sdk_app_name_hidden")
    fetch("/onboarding/source", {
      method: "POST",
      headers: { "Accept": "text/vnd.turbo-stream.html", "X-CSRF-Token": this.csrfToken() },
      body: new URLSearchParams({ "preview": "sdk" })
    }).then(r => r.text()).then(html => Turbo.renderStreamMessage(html))
  }
  copyAppName(targetId) {
    const v = document.getElementById("onboarding_app_name")?.value || ""
    document.querySelectorAll(`#${targetId}`).forEach(el => el.value = v)
  }
  csrfToken() { return document.querySelector("meta[name='csrf-token']")?.content }
}
