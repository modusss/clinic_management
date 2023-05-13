import { Controller } from "stimulus"

export default class extends Controller {
  static targets = ["fixed", "scrollable"]

  connect() {
    this.fixedTarget.addEventListener("scroll", this.syncScroll.bind(this))
    this.scrollableTarget.addEventListener("scroll", this.syncScroll.bind(this))
  }

  syncScroll(event) {
    if (event.target.id === "fixed") {
      this.scrollableTarget.scrollTop = event.target.scrollTop
    } else {
      this.fixedTarget.scrollTop = event.target.scrollTop
    }
  }
}
