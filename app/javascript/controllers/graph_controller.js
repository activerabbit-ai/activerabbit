import { Controller } from "@hotwired/stimulus"
import Chart from "chart.js/auto"

export default class extends Controller {
  static values = {
    labels: Array,
    counts: Array,
    range: String,
    secondarySeries: Array,
    secondarySeriesLabel: String
  }

  connect() {
    const ctx = this.element.getContext('2d')
    const data = {
      labels: this.labelsValue,
      datasets: [{
        label: `Events (${this.rangeValue})`,
        data: this.countsValue,
        backgroundColor: 'rgba(99, 102, 241, 0.7)',
        borderColor: 'rgba(99, 102, 241, 1)',
        borderWidth: 1,
        borderRadius: 3,
        barPercentage: 0.95,
        categoryPercentage: 0.95,
        yAxisID: 'y',
      }]
    }

    // Optional secondary line series (e.g., Avg ms)
    if (this.hasSecondarySeriesValue && Array.isArray(this.secondarySeriesValue) && this.secondarySeriesValue.length) {
      data.datasets.push({
        type: 'line',
        label: this.secondarySeriesLabelValue || 'Avg',
        data: this.secondarySeriesValue,
        borderColor: 'rgba(16, 185, 129, 1)',
        backgroundColor: 'rgba(16, 185, 129, 0.2)',
        borderWidth: 2,
        tension: 0.3,
        yAxisID: 'y1',
        pointRadius: 0,
      })
    }
    const options = {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: { display: false },
        tooltip: {
          callbacks: {
            title: (items) => items[0]?.label || '',
            label: (item) => {
              const dsLabel = item.dataset.label || 'Value'
              return `${dsLabel}: ${item.parsed.y}`
            }
          }
        }
      },
      scales: {
        x: {
          ticks: { color: '#6b7280', autoSkip: true, maxRotation: 0 },
          grid: { display: false }
        },
        y: {
          beginAtZero: true,
          ticks: { color: '#6b7280', stepSize: Math.max(1, Math.ceil(Math.max(...this.countsValue) / 4)) },
          grid: { color: '#f3f4f6' }
        },
        y1: {
          position: 'right',
          beginAtZero: true,
          ticks: { color: '#10b981' },
          grid: { drawOnChartArea: false }
        }
      }
    }
    this.chart = new Chart(ctx, { type: 'bar', data, options })
  }

  disconnect() {
    if (this.chart) {
      this.chart.destroy()
    }
  }
}


