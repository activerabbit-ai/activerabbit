import { Controller } from "@hotwired/stimulus"
import { marked } from "marked"
import hljs from "highlight.js"

// Stimulus controller to render Markdown with syntax highlighting
export default class extends Controller {
  static values = { content: String }

  connect() {
    marked.setOptions({
      highlight: function(code, lang) {
        if (lang && hljs.getLanguage(lang)) {
          return hljs.highlight(code, { language: lang }).value
        }
        return hljs.highlightAuto(code).value
      },
      breaks: true
    })

    const html = marked.parse(this.contentValue || "")
    this.element.innerHTML = html

    // Add spacing and typography classes
    this.element.querySelectorAll('p').forEach((el) => {
      el.classList.add('mb-3', 'leading-7', 'text-gray-800')
    })
    this.element.querySelectorAll('h1,h2,h3,h4').forEach((el) => {
      el.classList.add('mt-4', 'mb-2', 'font-semibold', 'text-gray-900')
    })
    this.element.querySelectorAll('ul,ol').forEach((el) => {
      el.classList.add('my-3', 'pl-6')
      if (el.tagName.toLowerCase() === 'ul') el.classList.add('list-disc')
      if (el.tagName.toLowerCase() === 'ol') el.classList.add('list-decimal')
    })
    // Block code
    this.element.querySelectorAll('pre').forEach((el) => {
      el.classList.add('rounded-lg', 'bg-gray-900', 'text-gray-100', 'p-4', 'overflow-x-auto', 'mb-4')
    })
    // Inline code (code not inside pre)
    this.element.querySelectorAll('code').forEach((el) => {
      if (el.parentElement && el.parentElement.tagName.toLowerCase() !== 'pre') {
        el.classList.add('bg-gray-100', 'text-gray-800', 'px-1.5', 'py-0.5', 'rounded')
      }
    })
  }
}


