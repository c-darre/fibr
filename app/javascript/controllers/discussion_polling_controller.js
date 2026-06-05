import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { waiting: Boolean }

  connect() {
    if (this.waitingValue) {
      this.pollingInterval = setInterval(() => window.location.reload(), 2000)
    }
  }

  disconnect() {
    clearInterval(this.pollingInterval)
  }
}
