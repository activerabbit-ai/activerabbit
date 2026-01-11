import { Controller } from "@hotwired/stimulus"
import { marked } from "marked"
import hljs from "highlight.js"

// Stimulus controller to render Markdown with syntax highlighting
export default class extends Controller {
  static targets = ["source"]
  static values = { content: String }

  connect() {
    // Get content from template tag or value attribute
    let content = ""
    if (this.hasSourceTarget) {
      content = this.sourceTarget.innerHTML
    } else if (this.hasContentValue) {
      content = this.contentValue
    }

    if (!content || content.trim() === "") {
      this.element.innerHTML = '<p class="text-gray-500 text-sm">No content available</p>'
      return
    }

    // Configure marked with syntax highlighting
    marked.setOptions({
      highlight: function(code, lang) {
        if (lang && hljs.getLanguage(lang)) {
          return hljs.highlight(code, { language: lang }).value
        }
        return hljs.highlightAuto(code).value
      },
      breaks: true,
      gfm: true
    })

    const html = marked.parse(content)
    this.element.innerHTML = html

    // Style headings (## Root Cause, ## Fix, etc.)
    this.element.querySelectorAll('h2').forEach((el) => {
      el.classList.add(
        'text-lg', 'font-bold', 'text-slate-800',
        'mt-5', 'mb-3', 'pb-2', 'border-b', 'border-slate-200',
        'flex', 'items-center', 'gap-2'
      )
      // Add icon based on heading text
      const text = el.textContent.toLowerCase()
      let icon = ''
      if (text.includes('root cause')) {
        icon = '<span class="w-6 h-6 rounded-md bg-red-100 text-red-600 flex items-center justify-center text-sm">🔍</span>'
      } else if (text.includes('fix')) {
        icon = '<span class="w-6 h-6 rounded-md bg-emerald-100 text-emerald-600 flex items-center justify-center text-sm">🔧</span>'
      } else if (text.includes('prevention')) {
        icon = '<span class="w-6 h-6 rounded-md bg-amber-100 text-amber-600 flex items-center justify-center text-sm">🛡️</span>'
      }
      if (icon) {
        el.innerHTML = icon + '<span>' + el.textContent + '</span>'
      }
    })

    this.element.querySelectorAll('h3').forEach((el) => {
      el.classList.add('text-base', 'font-semibold', 'text-slate-700', 'mt-4', 'mb-2')
    })

    // Style paragraphs
    this.element.querySelectorAll('p').forEach((el) => {
      el.classList.add('mb-3', 'leading-relaxed', 'text-slate-700', 'text-sm')
    })

    // Style lists
    this.element.querySelectorAll('ul').forEach((el) => {
      el.classList.add('my-3', 'pl-5', 'list-disc', 'space-y-1.5', 'text-sm', 'text-slate-700')
    })
    this.element.querySelectorAll('ol').forEach((el) => {
      el.classList.add('my-3', 'pl-5', 'list-decimal', 'space-y-1.5', 'text-sm', 'text-slate-700')
    })
    this.element.querySelectorAll('li').forEach((el) => {
      el.classList.add('leading-relaxed')
    })

    // Style code blocks (like editor)
    this.element.querySelectorAll('pre').forEach((el) => {
      // Create wrapper with header
      const wrapper = document.createElement('div')
      wrapper.classList.add(
        'rounded-xl', 'overflow-hidden', 'my-4',
        'border', 'border-slate-700', 'shadow-lg'
      )

      // Editor header bar
      const header = document.createElement('div')
      header.classList.add(
        'bg-slate-800', 'px-4', 'py-2',
        'flex', 'items-center', 'gap-2', 'border-b', 'border-slate-700'
      )
      header.innerHTML = `
        <span class="w-3 h-3 rounded-full bg-red-500"></span>
        <span class="w-3 h-3 rounded-full bg-yellow-500"></span>
        <span class="w-3 h-3 rounded-full bg-green-500"></span>
        <span class="ml-2 text-xs text-slate-400 font-mono">code</span>
      `

      // Style the pre element
      el.classList.add(
        'bg-slate-900', 'text-slate-100',
        'p-4', 'overflow-x-auto', 'm-0',
        'text-sm', 'leading-relaxed', 'font-mono'
      )

      // Wrap
      el.parentNode.insertBefore(wrapper, el)
      wrapper.appendChild(header)
      wrapper.appendChild(el)
    })

    // Style inline code
    this.element.querySelectorAll('code').forEach((el) => {
      if (el.parentElement && el.parentElement.tagName.toLowerCase() !== 'pre') {
        el.classList.add(
          'bg-indigo-50', 'text-indigo-700',
          'px-1.5', 'py-0.5', 'rounded-md',
          'text-sm', 'font-mono', 'font-medium'
        )
      }
    })

    // Style strong/bold
    this.element.querySelectorAll('strong').forEach((el) => {
      el.classList.add('font-semibold', 'text-slate-800')
    })

    // Style blockquotes
    this.element.querySelectorAll('blockquote').forEach((el) => {
      el.classList.add(
        'border-l-4', 'border-indigo-400', 'bg-indigo-50/50',
        'pl-4', 'py-2', 'my-3', 'text-sm', 'text-slate-600', 'italic'
      )
    })
  }
}
