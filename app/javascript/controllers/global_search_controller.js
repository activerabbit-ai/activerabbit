import { Controller } from "@hotwired/stimulus"

// Sentry-style global search with keyboard shortcuts
export default class extends Controller {
  static targets = ["input"]

  connect() {
    // Listen for global keyboard shortcuts
    this.boundHandleGlobalKeydown = this.handleGlobalKeydown.bind(this)
    document.addEventListener("keydown", this.boundHandleGlobalKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundHandleGlobalKeydown)
  }

  handleGlobalKeydown(event) {
    // Cmd/Ctrl + K to focus search
    if ((event.metaKey || event.ctrlKey) && event.key === "k") {
      event.preventDefault()
      this.focusSearch()
      return
    }

    // "/" to focus search (when not in an input)
    if (event.key === "/" && !this.isInputFocused()) {
      event.preventDefault()
      this.focusSearch()
    }
  }

  handleKeydown(event) {
    // Escape to blur search
    if (event.key === "Escape") {
      this.inputTarget.blur()
    }
  }

  focusSearch() {
    this.inputTarget.focus()
    this.inputTarget.select()
  }

  isInputFocused() {
    const activeElement = document.activeElement
    const tagName = activeElement?.tagName?.toLowerCase()
    return tagName === "input" || tagName === "textarea" || activeElement?.isContentEditable
  }
}
