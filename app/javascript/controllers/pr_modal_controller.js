import { Controller } from "@hotwired/stimulus"

// Controller for the PR creation modal
export default class extends Controller {
  static targets = ["modal", "branchInput", "suggestedBranch", "form", "submitButton", "cancelButton", "loadingIndicator"]
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

    this.hideLoading()
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
    event.preventDefault()
    
    // Get form data
    const form = this.formTarget
    const formData = new FormData(form)
    
    // Show loading state - disable buttons and show spinner
    this.showLoading()
    
    // Get CSRF token
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    
    // Submit form via fetch
    fetch(form.action, {
      method: 'POST',
      body: formData,
      headers: {
        'X-Requested-With': 'XMLHttpRequest',
        'Accept': 'application/json',
        'X-CSRF-Token': csrfToken
      },
      credentials: 'same-origin'
    })
    .then(response => {
      if (!response.ok) {
        return response.json().then(data => {
          throw new Error(data.error || 'Failed to create PR')
        })
      }
      return response.json()
    })
    .then(data => {
      if (data.success && data.pr_url) {
        // Open PR in new tab immediately
        const prWindow = window.open(data.pr_url, '_blank', 'noopener,noreferrer')
        
        // Check if popup was blocked
        if (!prWindow || prWindow.closed || typeof prWindow.closed == 'undefined') {
          // Popup was blocked - create a temporary link and click it
          const link = document.createElement('a')
          link.href = data.pr_url
          link.target = '_blank'
          link.rel = 'noopener noreferrer'
          link.style.display = 'none'
          document.body.appendChild(link)
          link.click()
          document.body.removeChild(link)
        }
        
        // Wait a bit for server to save PR URL, then reload
        setTimeout(() => {
          this.hideLoading()
          this.close()
          window.location.reload()
        }, 1000) // 1 second should be enough for the server to save
      } else {
        throw new Error(data.error || 'Failed to create PR')
      }
    })
    .catch(error => {
      console.error('Error creating PR:', error)
      this.hideLoading()
      alert(`Failed to create PR: ${error.message}`)
      // Still try to poll, in case PR was created despite error
      this.pollForPR()
    })
  }

  showLoading() {
    // Disable submit button
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = true
      this.submitButtonTarget.value = "Creating PR..."
    }
    
    // Disable cancel button
    if (this.hasCancelButtonTarget) {
      this.cancelButtonTarget.disabled = true
    }
    
    // Show loading indicator
    if (this.hasLoadingIndicatorTarget) {
      this.loadingIndicatorTarget.classList.remove("hidden")
    }
  }

  hideLoading() {
    // Re-enable submit button
    if (this.hasSubmitButtonTarget) {
      this.submitButtonTarget.disabled = false
      this.submitButtonTarget.value = "Create PR"
    }
    
    // Re-enable cancel button
    if (this.hasCancelButtonTarget) {
      this.cancelButtonTarget.disabled = false
    }
    
    // Hide loading indicator
    if (this.hasLoadingIndicatorTarget) {
      this.loadingIndicatorTarget.classList.add("hidden")
    }
  }

  pollForPR() {
    // Poll every 500ms for up to 15 seconds to check if PR was created
    let attempts = 0
    const maxAttempts = 30 // 15 seconds total
    let prUrl = null
    
    const pollInterval = setInterval(() => {
      attempts++
      
      // Reload page to check if PR URL is now available
      fetch(window.location.href, {
        method: 'GET',
        headers: {
          'X-Requested-With': 'XMLHttpRequest',
          'Accept': 'text/html'
        },
        credentials: 'same-origin',
        cache: 'no-cache'
      })
      .then(response => response.text())
      .then(html => {
        // Check if PR link exists in the response
        const parser = new DOMParser()
        const doc = parser.parseFromString(html, 'text/html')
        const prLink = doc.querySelector('a[href*="github.com"][href*="/pull/"]')
        
        if (prLink) {
          prUrl = prLink.getAttribute('href')
          clearInterval(pollInterval)
          // Open PR in new tab if found
          if (prUrl) {
            window.open(prUrl, '_blank')
          }
          // Reload the page
          window.location.reload()
        } else if (attempts >= maxAttempts) {
          clearInterval(pollInterval)
          // Reload anyway after max attempts
          window.location.reload()
        }
      })
      .catch(() => {
        // On error, just reload after max attempts
        if (attempts >= maxAttempts) {
          clearInterval(pollInterval)
          window.location.reload()
        }
      })
    }, 500)
  }
}
