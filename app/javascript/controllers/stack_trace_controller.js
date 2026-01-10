import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="stack-trace"
export default class extends Controller {
  static targets = ["frame", "toggleButton", "filterBtn", "frameList"]
  static values = { filter: { type: String, default: "app" } }

  connect() {
    // Initialize frame states based on data-expanded attribute
    this.frameTargets.forEach(frame => {
      const isExpanded = frame.dataset.expanded === "true"
      this.updateFrameState(frame, isExpanded)
    })

    // Apply initial filter
    this.applyFilter(this.filterValue)
  }

  filterFrames(event) {
    const filter = event.currentTarget.dataset.filter
    this.filterValue = filter
    this.applyFilter(filter)
    this.updateFilterButtons(filter)
  }

  applyFilter(filter) {
    this.frameTargets.forEach(frame => {
      const isInApp = frame.dataset.inApp === "true"

      if (filter === "app") {
        // Show only in-app frames
        frame.style.display = isInApp ? "" : "none"
      } else {
        // Show all frames
        frame.style.display = ""
      }
    })

    // Update toggle button text based on visible frames
    this.updateToggleButtonText()
  }

  updateFilterButtons(activeFilter) {
    this.filterBtnTargets.forEach(btn => {
      const btnFilter = btn.dataset.filter
      const isActive = btnFilter === activeFilter

      if (isActive) {
        btn.classList.remove("bg-white", "text-gray-700", "hover:bg-gray-50")
        btn.classList.add("bg-indigo-600", "text-white")
        // Update badge color
        const badge = btn.querySelector("span")
        if (badge) {
          badge.classList.remove("bg-gray-200")
          badge.classList.add("bg-indigo-500")
        }
      } else {
        btn.classList.remove("bg-indigo-600", "text-white")
        btn.classList.add("bg-white", "text-gray-700", "hover:bg-gray-50")
        // Update badge color
        const badge = btn.querySelector("span")
        if (badge) {
          badge.classList.remove("bg-indigo-500")
          badge.classList.add("bg-gray-200")
        }
      }
    })
  }

  toggleFrame(event) {
    const frame = event.currentTarget.closest('[data-stack-trace-target="frame"]')
    if (!frame) return

    const isCurrentlyExpanded = frame.dataset.expanded === "true"
    this.updateFrameState(frame, !isCurrentlyExpanded)
  }

  toggleAllFrames() {
    const visibleFrames = this.frameTargets.filter(frame => frame.style.display !== "none")
    const anyCollapsed = visibleFrames.some(frame => frame.dataset.expanded !== "true")

    visibleFrames.forEach(frame => {
      this.updateFrameState(frame, anyCollapsed)
    })

    this.updateToggleButtonText()
  }

  updateToggleButtonText() {
    if (!this.hasToggleButtonTarget) return

    const visibleFrames = this.frameTargets.filter(frame => frame.style.display !== "none")
    const anyCollapsed = visibleFrames.some(frame => frame.dataset.expanded !== "true")
    this.toggleButtonTarget.textContent = anyCollapsed ? "Expand all frames" : "Collapse all frames"
  }

  updateFrameState(frame, expanded) {
    frame.dataset.expanded = expanded ? "true" : "false"

    // Update expand icon rotation
    const icon = frame.querySelector('.expand-icon')
    if (icon) {
      icon.style.transform = expanded ? 'rotate(90deg)' : 'rotate(0deg)'
    }

    // Show/hide content
    const content = frame.querySelector('.frame-content')
    if (content) {
      if (expanded) {
        content.classList.remove('hidden')
      } else {
        content.classList.add('hidden')
      }
    }
  }
}

