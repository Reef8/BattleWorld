// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/bracket_battle"
import topbar from "../vendor/topbar"

// Custom hooks
const Hooks = {
  ScrollToBottom: {
    mounted() {
      this.el.scrollTop = this.el.scrollHeight
    },
    updated() {
      this.el.scrollTop = this.el.scrollHeight
    }
  },
  TournamentStartReveal: {
    mounted() {
      const tournamentId = this.el.dataset.tournamentId
      const key = `tournament_started_seen_${tournamentId}`

      // Check if user has already seen the tournament start banner
      if (!localStorage.getItem(key)) {
        this.pushEvent("show_tournament_start", {})
      }

      // Listen for dismiss event to save to localStorage
      this.handleEvent("tournament_start_dismissed", ({tournament_id}) => {
        localStorage.setItem(`tournament_started_seen_${tournament_id}`, "true")
      })
    }
  },
  WelcomeSplash: {
    mounted() {
      const hasSeenWelcome = localStorage.getItem("bracket_battle_welcome_seen")

      if (!hasSeenWelcome) {
        this.pushEvent("show_welcome_splash", {})

        // Create particles after a short delay
        setTimeout(() => this.createParticles(), 400)

        // Auto-dismiss after animation completes (5 seconds)
        this.autoDismissTimer = setTimeout(() => {
          this.dismiss()
        }, 5000)
      }

      this.handleEvent("welcome_splash_dismissed", () => {
        localStorage.setItem("bracket_battle_welcome_seen", "true")
      })
    },

    createParticles() {
      const container = this.el
      const colors = ['#9333ea', '#a855f7', '#fbbf24', '#f59e0b', '#c084fc']

      // Create burst particles
      for (let i = 0; i < 20; i++) {
        const particle = document.createElement('div')
        particle.className = 'splash-particle'
        particle.style.background = colors[Math.floor(Math.random() * colors.length)]
        particle.style.left = '50%'
        particle.style.top = '45%'
        particle.style.animation = `particle-float ${1 + Math.random()}s ease-out ${Math.random() * 0.5}s forwards`
        particle.style.transform = `rotate(${Math.random() * 360}deg) translateX(${50 + Math.random() * 150}px)`
        container.appendChild(particle)
      }

      // Create shockwave rings
      for (let i = 0; i < 3; i++) {
        const ring = document.createElement('div')
        ring.className = 'splash-shockwave'
        ring.style.left = 'calc(50% - 100px)'
        ring.style.top = 'calc(45% - 100px)'
        ring.style.animationDelay = `${i * 0.3}s`
        container.appendChild(ring)
      }
    },

    dismiss() {
      if (this.autoDismissTimer) {
        clearTimeout(this.autoDismissTimer)
      }
      this.el.classList.add('splash-fade-out')
      this.pushEvent("dismiss_welcome_splash", {})
    }
  },
  TournamentCompleteReveal: {
    mounted() {
      const tournamentId = this.el.dataset.tournamentId
      const key = `tournament_complete_seen_${tournamentId}`

      // Check if user has already seen the tournament complete popup
      if (!localStorage.getItem(key)) {
        this.pushEvent("show_tournament_complete", {})
      }

      // Listen for dismiss event to save to localStorage
      this.handleEvent("tournament_complete_dismissed", ({tournament_id}) => {
        localStorage.setItem(`tournament_complete_seen_${tournament_id}`, "true")
      })
    }
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...Hooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}

