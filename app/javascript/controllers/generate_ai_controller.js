import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "buttonText", "spinner", "icon", "waitText", "quotaMessage"]
  static values  = { url: String, quotaExceeded: Boolean, upgradeUrl: String }

  generate(event) {
    event.preventDefault()

    // If quota exceeded, redirect to upgrade page
    if (this.quotaExceededValue) {
      if (this.upgradeUrlValue) {
        window.location.href = this.upgradeUrlValue
      }
      return
    }

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
        // Quota ran out mid-session — show inline upgrade card
        this.resetButton()
        this.showQuotaCard(data)
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

  showQuotaCard(data) {
    const upgradeUrl = data.upgrade_url || this.upgradeUrlValue || "/plan"
    const message = data.message || "AI analysis quota reached."
    const canBuyMore = data.can_buy_more || false

    const ctaLabel = canBuyMore ? "Buy More" : "Upgrade"
    const ctaSubtext = canBuyMore
      ? "Purchase additional AI analyses to keep going."
      : "Upgrade for more AI-powered root cause analysis."
    const ctaGradient = canBuyMore
      ? "from-emerald-600 to-teal-600 hover:from-emerald-700 hover:to-teal-700"
      : "from-indigo-600 to-violet-600 hover:from-indigo-700 hover:to-violet-700"
    const borderColor = canBuyMore ? "border-emerald-200" : "border-indigo-200"
    const bgGradient = canBuyMore
      ? "from-emerald-50 to-teal-50"
      : "from-indigo-50 to-violet-50"
    const ctaIcon = canBuyMore
      ? `<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6"></path>`
      : `<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 7h8m0 0v8m0-8l-8 8-4-4-6 6"></path>`

    // For "Buy More" use a form POST to billing portal; for "Upgrade" use a regular link
    const ctaHtml = canBuyMore
      ? `<form method="post" action="${upgradeUrl}" target="_blank" class="flex-shrink-0">
           <input type="hidden" name="authenticity_token" value="${document.querySelector('meta[name=csrf-token]')?.content || ''}">
           <button type="submit"
                   class="inline-flex items-center gap-1.5 px-4 py-2 text-sm font-semibold text-white bg-gradient-to-r ${ctaGradient} rounded-lg shadow transition-all cursor-pointer">
             <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">${ctaIcon}</svg>
             ${ctaLabel}
           </button>
         </form>`
      : `<a href="${upgradeUrl}"
            class="flex-shrink-0 inline-flex items-center gap-1.5 px-4 py-2 text-sm font-semibold text-white bg-gradient-to-r ${ctaGradient} rounded-lg shadow transition-all">
           <svg class="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">${ctaIcon}</svg>
           ${ctaLabel}
         </a>`

    // Replace the entire generate-ai container with a quota card
    this.element.innerHTML = `
      <div class="mt-2 rounded-xl border ${borderColor} bg-gradient-to-r ${bgGradient} p-4 shadow-sm">
        <div class="flex items-center gap-3">
          <div class="flex-shrink-0 w-10 h-10 bg-gradient-to-br from-indigo-500 to-violet-600 rounded-lg flex items-center justify-center">
            <svg class="w-5 h-5 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z"></path>
            </svg>
          </div>
          <div class="flex-1 min-w-0">
            <p class="text-sm font-medium text-gray-800">${message}</p>
            <p class="text-xs text-gray-500 mt-0.5">${ctaSubtext}</p>
          </div>
          ${ctaHtml}
        </div>
      </div>
    `
  }

  dismissQuota(event) {
    event.preventDefault()
    if (this.hasQuotaMessageTarget) {
      this.quotaMessageTarget.classList.add("hidden")
    }
  }
}
