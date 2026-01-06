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
import topbar from "../vendor/topbar"

// Custom hooks
const Hooks = {
  LocalTime: {
    mounted() {
      this.formatTime()
    },
    updated() {
      this.formatTime()
    },
    formatTime() {
      const utcTime = this.el.dataset.utc
      if (!utcTime) return

      const date = new Date(utcTime)
      if (isNaN(date.getTime())) return

      const format = this.el.dataset.format || "full"
      const options = this.getFormatOptions(format)

      // Format the date in user's local timezone
      const formatter = new Intl.DateTimeFormat(undefined, options)
      const formattedDate = formatter.format(date)

      // Get timezone abbreviation
      const tzFormatter = new Intl.DateTimeFormat(undefined, { timeZoneName: 'short' })
      const parts = tzFormatter.formatToParts(date)
      const tz = parts.find(p => p.type === 'timeZoneName')?.value || ''

      // Update the element content
      if (format === "relative") {
        this.el.textContent = this.getRelativeTime(date)
      } else {
        this.el.textContent = `${formattedDate} ${tz}`.trim()
      }

      // Store original UTC for tooltip
      this.el.title = `UTC: ${utcTime}`
    },
    getFormatOptions(format) {
      switch (format) {
        case "date":
          return { month: 'short', day: 'numeric', year: 'numeric' }
        case "time":
          return { hour: 'numeric', minute: '2-digit' }
        case "datetime":
          return { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }
        case "full":
        default:
          return {
            month: 'short',
            day: 'numeric',
            year: 'numeric',
            hour: 'numeric',
            minute: '2-digit'
          }
      }
    },
    getRelativeTime(date) {
      const now = new Date()
      const diff = date - now
      const absDiff = Math.abs(diff)

      const minutes = Math.floor(absDiff / 60000)
      const hours = Math.floor(absDiff / 3600000)
      const days = Math.floor(absDiff / 86400000)

      const isPast = diff < 0
      const suffix = isPast ? " ago" : ""
      const prefix = isPast ? "" : "in "

      if (minutes < 1) return "just now"
      if (minutes < 60) return `${prefix}${minutes}m${suffix}`
      if (hours < 24) return `${prefix}${hours}h${suffix}`
      return `${prefix}${days}d${suffix}`
    }
  },
  ScrollToBottom: {
    mounted() {
      this.el.scrollTop = this.el.scrollHeight
    },
    updated() {
      this.el.scrollTop = this.el.scrollHeight
    }
  },
  ResetForm: {
    mounted() {
      this.el.addEventListener("submit", () => {
        setTimeout(() => this.el.reset(), 0)
      })
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
  },
  BracketViewer: {
    mounted() {
      this.renderBracket()
    },
    updated() {
      this.renderBracket()
    },
    renderBracket() {
      const data = JSON.parse(this.el.dataset.bracket)
      const interactive = this.el.dataset.interactive === "true"
      const isSubmitted = this.el.dataset.submitted === "true"

      if (window.bracketsViewer && data.stages && data.stages.length > 0) {
        window.bracketsViewer.render({
          stages: data.stages,
          matches: data.matches,
          matchGames: data.matchGames || [],
          participants: data.participants,
        }, {
          selector: `#${this.el.id}`,
          clear: true,
          participantOriginPlacement: 'before',
          separatedChildCountLabel: true,
          showSlotsOrigin: true,
          highlightParticipantOnHover: true,
          onMatchClick: interactive && !isSubmitted ? (match) => {
            this.pushEvent("match_clicked", { match_id: match.id })
          } : undefined
        })

        // If interactive, add click handlers on participant names for picking
        if (interactive && !isSubmitted) {
          this.setupParticipantClicks()
        }
      }
    },
    setupParticipantClicks() {
      const container = this.el
      const self = this

      // Add click handlers to participant name elements
      setTimeout(() => {
        container.querySelectorAll('.participant .name').forEach(el => {
          const participantEl = el.closest('.participant')
          if (participantEl) {
            participantEl.style.cursor = 'pointer'
            participantEl.onclick = (e) => {
              e.stopPropagation()
              const matchEl = participantEl.closest('.match')
              if (matchEl) {
                // Get match and participant IDs from data attributes
                const matchId = matchEl.getAttribute('data-match-id')
                const isOpponent1 = participantEl.classList.contains('opponent1')
                self.pushEvent("pick_winner", {
                  match_id: matchId,
                  is_opponent1: isOpponent1
                })
              }
            }
          }
        })
      }, 100) // Small delay to ensure DOM is ready
    }
  }
}

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks,
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

