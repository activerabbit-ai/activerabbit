import { Controller } from "@hotwired/stimulus"

// Controller for the PR creation modal
export default class extends Controller {
  static targets = ["modal", "branchInput", "suggestedBranch", "form"]
  static values = {
    issueId: Number,
    exceptionClass: String,
    controllerAction: String
  }

  open(event) {
    event.preventDefault()
    this.modalTarget.classList.remove("hidden")
    // Generate suggested branch name based on error info
    this.generateSuggestedBranch()
    // Focus on branch input
    setTimeout(() => this.branchInputTarget.focus(), 100)
  }

  close(event) {
    if (event) event.preventDefault()
    this.modalTarget.classList.add("hidden")
    this.branchInputTarget.value = ""
  }

  closeOnBackdrop(event) {
    // Only close if clicking the backdrop (not the modal content)
    if (event.target === this.modalTarget) {
      this.close()
    }
  }

  closeOnEscape(event) {
    if (event.key === "Escape" && !this.modalTarget.classList.contains("hidden")) {
      this.close()
    }
  }

  generateSuggestedBranch() {
    // Generate a clean branch name from the error info
    const exceptionClass = this.exceptionClassValue || "error"
    const action = this.controllerActionValue || ""
    
    // Clean up the exception class for branch name
    let branchName = exceptionClass
      .replace(/Error$/, "")
      .replace(/Exception$/, "")
      .replace(/([a-z])([A-Z])/g, "$1-$2")
      .toLowerCase()
      .replace(/[^a-z0-9-]/g, "-")
      .replace(/-+/g, "-")
      .replace(/^-|-$/g, "")
    
    // Add action if present
    if (action) {
      const cleanAction = action
        .split("#").pop()
        .replace(/[^a-z0-9]/gi, "-")
        .toLowerCase()
      branchName = `${branchName}-${cleanAction}`
    }
    
    // Limit length
    if (branchName.length > 40) {
      branchName = branchName.substring(0, 40)
    }
    
    const suggested = `ai-fix/${branchName}`
    this.suggestedBranchTarget.textContent = suggested
  }

  useSuggested(event) {
    event.preventDefault()
    this.branchInputTarget.value = this.suggestedBranchTarget.textContent
  }

  submit(event) {
    // If no branch name provided, use AI-generated one (will be set on server)
    // Form will submit normally
  }
}
