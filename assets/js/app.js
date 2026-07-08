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

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"

// Palette storage hooks for localStorage
let Hooks = {}

Hooks.PaletteStorage = {
  mounted() {
    this.loadSavedPalettes()
    this.loadActivePalette()

    this.handleEvent("save_palette", (palette) => {
      this.savePalette(palette)
    })

    this.handleEvent("delete_palette", ({name}) => {
      this.deletePalette(name)
    })

    this.handleEvent("rename_palette", ({old_name, new_name}) => {
      this.renamePalette(old_name, new_name)
    })

    this.handleEvent("activate_palette", (palette) => {
      this.storeActivePalette(palette)
    })
  },

  loadSavedPalettes() {
    try {
      const saved = localStorage.getItem('color_matching_palettes')
      const palettes = saved ? JSON.parse(saved) : []
      this.pushEvent("palettes_updated", {palettes})
    } catch (e) {
      console.error("Error loading palettes:", e)
      this.pushEvent("palettes_updated", {palettes: []})
    }
  },

  // The "active palette" is the currently selected/edited palette, shared
  // across pages (and reloads) via localStorage so a future palette
  // management page can pick up right where the grid page left off, and
  // vice versa. See ColorMatching.PaletteStorage moduledoc for details.
  loadActivePalette() {
    try {
      const saved = localStorage.getItem('color_matching_active_palette')
      const palette = saved ? JSON.parse(saved) : null
      this.pushEvent("active_palette_loaded", {palette})
    } catch (e) {
      console.error("Error loading active palette:", e)
      this.pushEvent("active_palette_loaded", {palette: null})
    }
  },

  storeActivePalette(palette) {
    try {
      localStorage.setItem('color_matching_active_palette', JSON.stringify(palette))
    } catch (e) {
      console.error("Error storing active palette:", e)
    }
  },

  savePalette({name, colors, created_at}) {
    try {
      const saved = localStorage.getItem('color_matching_palettes')
      const palettes = saved ? JSON.parse(saved) : []

      const existing = palettes.find(p => p.name === name)
      const filtered = palettes.filter(p => p.name !== name)

      filtered.push({
        name: name,
        colors: colors,
        is_preset: false,
        created_at: created_at || existing?.created_at || new Date().toISOString()
      })

      localStorage.setItem('color_matching_palettes', JSON.stringify(filtered))
      this.loadSavedPalettes()
    } catch (e) {
      console.error("Error saving palette:", e)
    }
  },

  deletePalette(name) {
    try {
      const saved = localStorage.getItem('color_matching_palettes')
      const palettes = saved ? JSON.parse(saved) : []
      const filtered = palettes.filter(p => p.name !== name)
      
      localStorage.setItem('color_matching_palettes', JSON.stringify(filtered))
      this.loadSavedPalettes()
    } catch (e) {
      console.error("Error deleting palette:", e)
    }
  },

  renamePalette(oldName, newName) {
    try {
      const saved = localStorage.getItem('color_matching_palettes')
      const palettes = saved ? JSON.parse(saved) : []
      
      const palette = palettes.find(p => p.name === oldName)
      if (palette) {
        palette.name = newName
        localStorage.setItem('color_matching_palettes', JSON.stringify(palettes))
        this.loadSavedPalettes()
      }
    } catch (e) {
      console.error("Error renaming palette:", e)
    }
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: Hooks
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
// Debug logging disabled for cleaner console
// window.liveSocket = liveSocket
