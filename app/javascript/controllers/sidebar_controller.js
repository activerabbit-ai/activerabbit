import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="sidebar"
export default class extends Controller {
  static targets = ["sidebar", "content", "toggleButton", "toggleTooltip", "brandText", "navText", "promoBox", "trialBox"]

  connect() {
    // The inline <script> in admin.html.erb already applies collapsed classes
    // before this controller connects (via turbo:before-render and DOMContentLoaded).
    // We just need to ensure internal state is consistent.
    const isCollapsed = localStorage.getItem('sidebarCollapsed') === 'true'
    if (isCollapsed && !this.sidebarTarget.classList.contains('sidebar-collapsed')) {
      // Fallback: apply collapsed state if the inline script didn't run
      this.collapse(false)
    }

    // Setup tooltip hover events
    this.setupTooltips()
  }
  
  setupTooltips() {
    // Create tooltip element
    this.tooltip = document.createElement('div')
    this.tooltip.className = 'sidebar-tooltip-popup'
    document.body.appendChild(this.tooltip)
    
    // Add hover events to nav items
    const navItems = this.sidebarTarget.querySelectorAll('.sidebar-nav-item')
    navItems.forEach(item => {
      item.addEventListener('mouseenter', (e) => this.showTooltip(e))
      item.addEventListener('mouseleave', () => this.hideTooltip())
    })
  }
  
  showTooltip(event) {
    // Only show tooltip when sidebar is collapsed
    if (!this.sidebarTarget.classList.contains('sidebar-collapsed')) {
      return
    }
    
    const item = event.currentTarget
    const tooltipText = item.querySelector('.sidebar-tooltip')?.textContent || 
                        item.querySelector('[data-sidebar-target="navText"]')?.textContent ||
                        item.getAttribute('title') || ''
    
    if (!tooltipText.trim()) return
    
    this.tooltip.textContent = tooltipText.trim()
    
    // Position tooltip to the right of the item
    const rect = item.getBoundingClientRect()
    this.tooltip.style.left = `${rect.right + 10}px`
    this.tooltip.style.top = `${rect.top + rect.height / 2}px`
    this.tooltip.style.transform = 'translateY(-50%)'
    
    this.tooltip.classList.add('visible')
  }
  
  hideTooltip() {
    this.tooltip.classList.remove('visible')
  }
  
  disconnect() {
    // Clean up tooltip
    if (this.tooltip) {
      this.tooltip.remove()
    }
  }

  toggle() {
    const sidebar = this.sidebarTarget
    const isCollapsed = sidebar.classList.contains('sidebar-collapsed')
    
    if (isCollapsed) {
      this.expand()
    } else {
      this.collapse()
    }
  }

  collapse(animate = true) {
    const sidebar = this.sidebarTarget
    const content = this.contentTarget
    
    // Add collapsed class
    sidebar.classList.add('sidebar-collapsed')
    sidebar.classList.remove('w-64', 'p-4')
    sidebar.classList.add('w-16', 'p-2')
    
    // Allow tooltips to overflow - remove overflow hidden from nav
    const nav = sidebar.querySelector('nav')
    if (nav) {
      nav.classList.remove('overflow-y-auto')
      nav.classList.add('overflow-visible')
    }
    
    // Update main content margin
    content.classList.remove('ml-64')
    content.classList.add('ml-16')
    
    // Hide text elements
    this.brandTextTargets.forEach(el => el.classList.add('hidden'))
    this.navTextTargets.forEach(el => el.classList.add('hidden'))
    
    // Hide promo and trial boxes
    if (this.hasPromoBoxTarget) {
      this.promoBoxTarget.classList.add('hidden')
    }
    if (this.hasTrialBoxTarget) {
      this.trialBoxTarget.classList.add('hidden')
    }
    
    // Center nav icons when collapsed
    this.centerNavIcons(true)
    
    // Update toggle button icon and tooltip
    this.updateToggleButton(true)
    
    // Save state and sync CSS class on <html>
    localStorage.setItem('sidebarCollapsed', 'true')
    document.documentElement.classList.add('sidebar-is-collapsed')
  }

  expand() {
    const sidebar = this.sidebarTarget
    const content = this.contentTarget
    
    // Remove collapsed class
    sidebar.classList.remove('sidebar-collapsed')
    sidebar.classList.remove('w-16', 'p-2')
    sidebar.classList.add('w-64', 'p-4')
    
    // Restore nav overflow for scrolling
    const nav = sidebar.querySelector('nav')
    if (nav) {
      nav.classList.remove('overflow-visible')
      nav.classList.add('overflow-y-auto')
    }
    
    // Update main content margin
    content.classList.remove('ml-16')
    content.classList.add('ml-64')
    
    // Show text elements
    this.brandTextTargets.forEach(el => el.classList.remove('hidden'))
    this.navTextTargets.forEach(el => el.classList.remove('hidden'))
    
    // Show promo and trial boxes
    if (this.hasPromoBoxTarget) {
      this.promoBoxTarget.classList.remove('hidden')
    }
    if (this.hasTrialBoxTarget) {
      this.trialBoxTarget.classList.remove('hidden')
    }
    
    // Restore nav icons alignment
    this.centerNavIcons(false)
    
    // Update toggle button icon and tooltip
    this.updateToggleButton(false)
    
    // Save state and sync CSS class on <html>
    localStorage.setItem('sidebarCollapsed', 'false')
    document.documentElement.classList.remove('sidebar-is-collapsed')
  }

  centerNavIcons(collapsed) {
    // Find all nav links and the toggle button
    const navLinks = this.sidebarTarget.querySelectorAll('nav a, button[data-action*="sidebar#toggle"]')
    
    navLinks.forEach(link => {
      if (collapsed) {
        // Center icons when collapsed
        link.classList.add('justify-center')
        link.classList.remove('px-4')
        link.classList.add('px-2')
        // Remove margin from icons
        const icon = link.querySelector('svg')
        if (icon) {
          icon.classList.remove('mr-3')
          icon.classList.add('mr-0')
        }
      } else {
        // Restore alignment
        link.classList.remove('justify-center')
        link.classList.remove('px-2')
        link.classList.add('px-4')
        // Restore margin to icons
        const icon = link.querySelector('svg')
        if (icon) {
          icon.classList.remove('mr-0')
          icon.classList.add('mr-3')
        }
      }
    })

    // Handle brand link
    const brandLink = this.sidebarTarget.querySelector('a[href="/"]') || this.sidebarTarget.querySelector('.flex.items-center.mb-6 a')
    if (brandLink) {
      if (collapsed) {
        brandLink.classList.add('justify-center')
      } else {
        brandLink.classList.remove('justify-center')
      }
    }
  }

  updateToggleButton(isCollapsed) {
    const button = this.toggleButtonTarget
    const icon = button.querySelector('svg')
    const text = button.querySelector('span[data-sidebar-target="navText"]')
    
    if (isCollapsed) {
      // Show expand icon (arrow right / open) - sidebar panel icon
      icon.innerHTML = `<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 5l7 7-7 7M5 5l7 7-7 7"></path>`
      if (text) text.textContent = ''
      // Update tooltip text
      if (this.hasToggleTooltipTarget) {
        this.toggleTooltipTarget.textContent = 'Open sidebar'
      }
    } else {
      // Show collapse icon (arrow left / close)
      icon.innerHTML = `<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 19l-7-7 7-7m8 14l-7-7 7-7"></path>`
      if (text) text.textContent = 'Close sidebar'
      // Update tooltip text
      if (this.hasToggleTooltipTarget) {
        this.toggleTooltipTarget.textContent = 'Close sidebar'
      }
    }
  }
}
