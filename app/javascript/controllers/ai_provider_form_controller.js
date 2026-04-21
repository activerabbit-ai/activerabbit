import { Controller } from "@hotwired/stimulus"

const DEFAULTS = {
  anthropic: { fast: "claude-haiku-4-5-20251001", power: "claude-sonnet-4-6" },
  openai:    { fast: "gpt-4o-mini", power: "gpt-4o" },
  gemini:    { fast: "gemini-2.0-flash", power: "gemini-2.5-pro" }
}

export default class extends Controller {
  static targets = ["provider", "fastModel", "powerModel", "fastDropdown", "powerDropdown", "fastSearch", "powerSearch", "fastDisplay", "powerDisplay"]
  static values = { modelsUrl: String }

  connect() {
    this.closeAll = this.closeAll.bind(this)
    document.addEventListener("click", this.closeAll)
    this.models = { fast: [], power: [] }
  }

  disconnect() {
    document.removeEventListener("click", this.closeAll)
  }

  async providerChanged() {
    const provider = this.providerTarget.value
    if (!provider) {
      this.models = { fast: [], power: [] }
      this.clearDropdown("fast")
      this.clearDropdown("power")
      return
    }

    // Show loading state
    this.fastDisplayTarget.textContent = "Loading models..."
    this.fastDisplayTarget.classList.add("text-gray-400")
    this.powerDisplayTarget.textContent = "Loading models..."
    this.powerDisplayTarget.classList.add("text-gray-400")

    try {
      const response = await fetch(`${this.modelsUrlValue}?provider=${provider}`)
      this.models = await response.json()
      this.populateDropdown("fast", this.models.fast, DEFAULTS[provider]?.fast)
      this.populateDropdown("power", this.models.power, DEFAULTS[provider]?.power)
    } catch (e) {
      this.fastDisplayTarget.textContent = "Failed to load models"
      this.powerDisplayTarget.textContent = "Failed to load models"
    }
  }

  populateDropdown(type, models, defaultValue) {
    const hiddenInput = type === "fast" ? this.fastModelTarget : this.powerModelTarget
    const display = type === "fast" ? this.fastDisplayTarget : this.powerDisplayTarget
    const dropdown = type === "fast" ? this.fastDropdownTarget : this.powerDropdownTarget

    if (!hiddenInput.value && defaultValue) {
      hiddenInput.value = defaultValue
    }

    const selected = hiddenInput.value
    const match = models.find(m => m.value === selected)
    if (match) {
      display.textContent = match.label
      display.classList.remove("text-gray-400")
      display.classList.add("text-gray-900")
    } else if (defaultValue) {
      const def = models.find(m => m.value === defaultValue)
      if (def) {
        hiddenInput.value = def.value
        display.textContent = def.label
        display.classList.remove("text-gray-400")
        display.classList.add("text-gray-900")
      }
    } else {
      display.textContent = "Select model..."
      display.classList.add("text-gray-400")
      display.classList.remove("text-gray-900")
    }

    this.renderOptions(dropdown, models, hiddenInput.value, defaultValue)
  }

  clearDropdown(type) {
    const display = type === "fast" ? this.fastDisplayTarget : this.powerDisplayTarget
    const dropdown = type === "fast" ? this.fastDropdownTarget : this.powerDropdownTarget
    const hiddenInput = type === "fast" ? this.fastModelTarget : this.powerModelTarget

    display.textContent = "Select a provider first"
    display.classList.add("text-gray-400")
    display.classList.remove("text-gray-900")
    hiddenInput.value = ""
    dropdown.innerHTML = ""
  }

  renderOptions(dropdown, models, selectedValue, defaultValue) {
    dropdown.innerHTML = models.map(m => `
      <button type="button"
        data-value="${m.value}"
        data-action="click->ai-provider-form#selectOption"
        class="model-option w-full text-left px-3 py-2 text-sm hover:bg-indigo-50 flex items-center justify-between ${m.value === selectedValue ? 'bg-indigo-50 text-indigo-700' : 'text-gray-700'}">
        <span>
          <span class="font-medium">${m.label}</span>
          <span class="text-xs text-gray-400 ml-1">${m.value}</span>
        </span>
        ${m.value === defaultValue ? '<span class="text-xs text-indigo-500">default</span>' : ''}
      </button>
    `).join("")
  }

  toggleFast(event) {
    event.preventDefault()
    event.stopPropagation()
    if (!this.providerTarget.value) return
    this.powerDropdownTarget.parentElement.classList.add("hidden")
    this.fastDropdownTarget.parentElement.classList.toggle("hidden")
    if (!this.fastDropdownTarget.parentElement.classList.contains("hidden")) {
      this.fastSearchTarget.value = ""
      this.fastSearchTarget.focus()
      this.filterOptions("fast", "")
    }
  }

  togglePower(event) {
    event.preventDefault()
    event.stopPropagation()
    if (!this.providerTarget.value) return
    this.fastDropdownTarget.parentElement.classList.add("hidden")
    this.powerDropdownTarget.parentElement.classList.toggle("hidden")
    if (!this.powerDropdownTarget.parentElement.classList.contains("hidden")) {
      this.powerSearchTarget.value = ""
      this.powerSearchTarget.focus()
      this.filterOptions("power", "")
    }
  }

  filterFast() {
    this.filterOptions("fast", this.fastSearchTarget.value)
  }

  filterPower() {
    this.filterOptions("power", this.powerSearchTarget.value)
  }

  filterOptions(type, query) {
    const dropdown = type === "fast" ? this.fastDropdownTarget : this.powerDropdownTarget
    const q = query.toLowerCase()
    dropdown.querySelectorAll(".model-option").forEach(el => {
      const text = el.textContent.toLowerCase()
      el.style.display = text.includes(q) ? "" : "none"
    })
  }

  selectOption(event) {
    event.preventDefault()
    event.stopPropagation()
    const btn = event.currentTarget
    const value = btn.dataset.value
    const dropdownEl = btn.closest("[data-dropdown-wrapper]")
    const type = dropdownEl.dataset.dropdownType

    const hiddenInput = type === "fast" ? this.fastModelTarget : this.powerModelTarget
    const display = type === "fast" ? this.fastDisplayTarget : this.powerDisplayTarget
    const models = this.models[type] || []

    hiddenInput.value = value
    const match = models.find(m => m.value === value)
    if (match) {
      display.textContent = match.label
      display.classList.remove("text-gray-400")
      display.classList.add("text-gray-900")
    }

    const dropdown = type === "fast" ? this.fastDropdownTarget : this.powerDropdownTarget
    dropdown.querySelectorAll(".model-option").forEach(el => {
      el.classList.toggle("bg-indigo-50", el.dataset.value === value)
      el.classList.toggle("text-indigo-700", el.dataset.value === value)
    })

    dropdownEl.classList.add("hidden")
  }

  closeAll(event) {
    if (!this.element.contains(event.target)) {
      this.fastDropdownTarget.parentElement.classList.add("hidden")
      this.powerDropdownTarget.parentElement.classList.add("hidden")
    }
  }
}
