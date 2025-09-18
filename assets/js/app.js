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
import {hooks as colocatedHooks} from "phoenix-colocated/the_maestro"
import topbar from "../vendor/topbar"
import Sortable from "sortablejs"

const Hooks = {}

Hooks.PromptSortable = {
  mounted() { this.initSortable() },
  updated() { this.destroySortable(); this.initSortable() },
  destroyed() { this.destroySortable() },
  initSortable() {
    if (this.el.dataset.disabled === 'true') return
    if (this.sortable) return
    const provider = this.el.dataset.provider
    if (!provider) return
    this.sortable = new Sortable(this.el, {
      animation: 160,
      handle: '.prompt-handle',
      ghostClass: 'opacity-60',
      onEnd: () => {
        const orderedIds = Array.from(this.el.querySelectorAll('[data-prompt-id]')).map(el => el.dataset.promptId)
        if (orderedIds.length === 0) return
        this.pushEvent('prompt_picker:reorder', {provider, ordered_ids: orderedIds})
      }
    })
  },
  destroySortable() {
    if (this.sortable) {
      this.sortable.destroy()
      this.sortable = null
    }
  }
}

Hooks.HamburgerToggle = {
  mounted() {
    this.targetId = this.el.getAttribute('data-target')
    this.el.setAttribute('aria-expanded', 'false')

    this.onClick = (e) => {
      e.stopPropagation()
      if (!this.targetId) return
      const target = document.getElementById(this.targetId)
      if (!target) return
      const nowHidden = target.classList.toggle('hidden')
      this.el.setAttribute('aria-expanded', nowHidden ? 'false' : 'true')

      // Add click outside listener when menu is opened
      if (!nowHidden) {
        this.setupClickOutside(target)
      }
    }

    this.clickOutside = (e) => {
      const target = document.getElementById(this.targetId)
      if (!target) return
      if (!target.contains(e.target) && !this.el.contains(e.target)) {
        target.classList.add('hidden')
        this.el.setAttribute('aria-expanded', 'false')
        document.removeEventListener('click', this.clickOutside)
      }
    }

    this.setupClickOutside = (target) => {
      // Small delay to avoid immediate closure
      setTimeout(() => {
        document.addEventListener('click', this.clickOutside)
      }, 10)
    }

    this.el.addEventListener('click', this.onClick)
  },
  destroyed() {
    this.el.removeEventListener('click', this.onClick)
    document.removeEventListener('click', this.clickOutside)
  }
}

Hooks.DirPickerNav = {
  mounted() {
    this.onKeydown = (e) => {
      // Ignore if typing in inputs/textareas except our filter
      const tag = e.target.tagName.toLowerCase()
      const isEditable = tag === 'input' || tag === 'textarea' || e.target.isContentEditable
      const isFilter = e.target.classList && e.target.classList.contains('dp-filter')
      if (isEditable && !isFilter) return

      const op = (k) => this.pushEventTo(this.el, 'dp_nav', {op: k})

      switch (e.key) {
        case 'ArrowDown': e.preventDefault(); op('down'); break;
        case 'ArrowUp': e.preventDefault(); op('up'); break;
        case 'Home': e.preventDefault(); op('home'); break;
        case 'End': e.preventDefault(); op('end'); break;
        case 'PageUp': e.preventDefault(); op('page_up'); break;
        case 'PageDown': e.preventDefault(); op('page_down'); break;
        case 'Enter':
          e.preventDefault()
          if (e.metaKey || e.ctrlKey) {
            this.pushEventTo(this.el, 'choose_here', {})
          } else {
            this.pushEventTo(this.el, 'enter_selected', {})
          }
          break;
        case 'Escape':
          e.preventDefault(); this.pushEventTo(this.el, 'cancel', {}); break;
        case 'f':
          if (!isEditable) {
            const inp = this.el.querySelector('.dp-filter')
            if (inp) { inp.focus(); inp.select(); }
          }
          break;
        default:
          if (!isEditable && e.key.length === 1 && !e.metaKey && !e.ctrlKey && !e.altKey) {
            const inp = this.el.querySelector('.dp-filter')
            if (inp) {
              inp.focus()
              // append the typed char and trigger input
              const v = (inp.value || '') + e.key
              inp.value = v
              inp.dispatchEvent(new Event('input', {bubbles: true}))
            }
          }
      }
    }
    window.addEventListener('keydown', this.onKeydown)
  },
  destroyed() { window.removeEventListener('keydown', this.onKeydown) }
}

Hooks.ChatInput = {
  mounted() {
    this.onKeydown = (e) => {
      if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
        e.preventDefault()
        this.pushEvent('send', {})
      }
    }
    this.el.addEventListener('keydown', this.onKeydown)
  },
  destroyed() { this.el.removeEventListener('keydown', this.onKeydown) }
}

Hooks.DashboardHotkeys = {
  mounted() {
    this.onKeydown = (e) => {
      const tag = e.target.tagName.toLowerCase()
      const isEditable = tag === 'input' || tag === 'textarea' || e.target.isContentEditable
      if (isEditable) return
      if (e.altKey && (e.key === 'n' || e.key === 'N')) { e.preventDefault(); this.pushEvent('open_session_modal', {}) }
      if (e.altKey && (e.key === 'a' || e.key === 'A')) { e.preventDefault(); this.pushEvent('open_agent_modal', {}) }
    }
    window.addEventListener('keydown', this.onKeydown)
  },
  destroyed() { window.removeEventListener('keydown', this.onKeydown) }
}

Hooks.AutoFocusModal = {
  mounted() {
    // Delay slightly to allow transition + DOM settling
    setTimeout(() => {
      try {
        const root = this.el
        // Prefer [autofocus], then inputs/textareas/selects/contenteditable
        const preferred = root.querySelector('[autofocus], [data-autofocus]')
        const firstInput = preferred || root.querySelector(
          'input:not([type=hidden]):not([disabled]):not([tabindex="-1"]), textarea:not([disabled]), select:not([disabled]), [contenteditable="true"]'
        )
        if (firstInput && typeof firstInput.focus === 'function') {
          firstInput.focus({preventScroll: true})
          // If it's a text field, place cursor at end
          if (firstInput.select && (firstInput.tagName === 'INPUT' || firstInput.tagName === 'TEXTAREA')) {
            const len = firstInput.value?.length || 0
            try { firstInput.setSelectionRange(len, len) } catch (_) {}
          }
        }
      } catch (_) { /* ignore */ }
    }, 30)
  }
}

Hooks.ShortcutsHint = {
  mounted() {
    this.el.addEventListener('click', (e) => {
      e.preventDefault()
      const evt = new KeyboardEvent('keydown', {key: '/', shiftKey: true})
      window.dispatchEvent(evt)
    })
  }
}

Hooks.GlobalHotkeys = {
  mounted() {
    this.seq = []
    this.seqTimer = null
    this.seqWindowMs = 1200

    const resetSeq = () => {
      this.seq = []
      if (this.seqTimer) { clearTimeout(this.seqTimer); this.seqTimer = null }
    }

    const scheduleReset = () => {
      if (this.seqTimer) clearTimeout(this.seqTimer)
      this.seqTimer = setTimeout(resetSeq, this.seqWindowMs)
    }

    const normalizeKey = (e) => {
      const k = (e.key || '').toLowerCase()
      if (k === ' ') return 'space'
      if (k.length === 1) return k
      return k
    }

    const collectHotkeys = () => {
      const singles = Array.from(document.querySelectorAll('[data-hotkey]'))
        .map(el => ({el, combo: (el.getAttribute('data-hotkey') || '').trim(), label: el.getAttribute('data-hotkey-label') || el.getAttribute('aria-label') || el.innerText || el.value || ''}))
        .filter(x => x.combo)

      const seqs = Array.from(document.querySelectorAll('[data-hotkey-seq]'))
        .map(el => ({
          el,
          seq: (el.getAttribute('data-hotkey-seq') || '').split(/\s+/).filter(Boolean),
          label: el.getAttribute('data-hotkey-label') || el.getAttribute('aria-label') || el.innerText || el.value || ''
        }))
        .filter(x => x.seq.length > 0)

      return {singles, seqs}
    }

    const isEditable = (t) => {
      const tag = t.tagName?.toLowerCase()
      return tag === 'input' || tag === 'textarea' || t.isContentEditable
    }

    this.onKeydown = (e) => {
      // Don't trigger inside editable fields
      if (isEditable(e.target)) return
      // Help overlay: "?" (Shift + /)
      if (e.key === '?' || (e.key === '/' && e.shiftKey)) {
        e.preventDefault()
        const items = []
        const seen = new Set()
        const {singles, seqs} = collectHotkeys()
        singles.forEach(({combo, label}) => {
          label = (label || '').trim().replace(/\s+/g, ' ')
          const key = combo + '|' + label
          if (!seen.has(key)) { seen.add(key); items.push({combo, label}) }
        })
        seqs.forEach(({seq, label}) => {
          const combo = seq.join(' then ')
          label = (label || '').trim().replace(/\s+/g, ' ')
          const key = combo + '|' + label
          if (!seen.has(key)) { seen.add(key); items.push({combo, label}) }
        })
        // Contextual additions
        if (document.querySelector('.dp-filter')) {
          items.push({combo: '↑/↓, Home/End, PgUp/PgDn', label: 'Navigate folders'})
          items.push({combo: 'Enter', label: 'Enter highlighted folder'})
          items.push({combo: 'Ctrl/Cmd+Enter', label: 'Choose here'})
          items.push({combo: 'f', label: 'Focus filter'})
          items.push({combo: 'type', label: 'Type-to-filter'})
          items.push({combo: 'Esc', label: 'Cancel'})
        }
        if (document.getElementById('chat-input')) {
          items.push({combo: 'Ctrl/Cmd+Enter', label: 'Send message'})
        }
        // Context: Generic Forms
        const hasForm = !!document.querySelector('form')
        if (hasForm) {
          items.push({combo: 'Tab / Shift+Tab', label: 'Move between fields'})
          const hasTextarea = !!document.querySelector('form textarea')
          if (hasTextarea) {
            items.push({combo: 'Enter', label: 'Submit form (except in multiline fields)'})
          } else {
            items.push({combo: 'Enter', label: 'Submit form'})
          }
          const inDialog = !!document.querySelector('[role="dialog"]')
          if (inDialog) items.push({combo: 'Esc', label: 'Close dialog'})
        }
        this.pushEventTo('#shortcuts-overlay', 'set', {items})
        this.pushEventTo('#shortcuts-overlay', 'toggle', {})
        return
      }
      const parts = []
      if (e.ctrlKey) parts.push('ctrl')
      if (e.metaKey) parts.push('meta')
      if (e.altKey) parts.push('alt')
      if (e.shiftKey) parts.push('shift')
      const normKey = normalizeKey(e)
      parts.push(normKey)
      const combo = parts.join('+')
      const el = document.querySelector(`[data-hotkey="${combo}"]`)
      if (el) {
        e.preventDefault()
        el.click()
        resetSeq()
        return
      }

      // Sequence handling – only single keys without modifiers
      if (!e.ctrlKey && !e.metaKey && !e.altKey && normKey.length === 1) {
        // Append key and schedule reset
        this.seq.push(normKey)
        scheduleReset()
        const {seqs} = collectHotkeys()
        const joined = this.seq.join(' ')
        const exact = seqs.find(x => x.seq.join(' ') === joined)
        if (exact) {
          e.preventDefault()
          exact.el.click()
          resetSeq()
          return
        }
        // If no sequence starts with current prefix, collapse to last key and check prefix again
        const hasPrefix = seqs.some(x => x.seq.join(' ').startsWith(joined))
        if (!hasPrefix) {
          this.seq = [normKey]
          const prefix = seqs.some(x => x.seq[0] === normKey)
          if (!prefix) resetSeq()
        }
        // show/update sequence bubble
        const existing = document.getElementById('hotkey-seq')
        if (this.seq.length === 0) { if (existing) existing.remove() } else {
          let el = existing || document.createElement('div')
          el.id = 'hotkey-seq'
          el.className = 'fixed bottom-3 left-3 z-50 px-2 py-1 rounded text-xs border border-amber-600 bg-black/80 text-amber-300'
          el.textContent = this.seq.join(' ') + ' …'
          if (!existing) document.body.appendChild(el)
        }
        return
      }
    }
    window.addEventListener('keydown', this.onKeydown)
  },
  destroyed() { window.removeEventListener('keydown', this.onKeydown) }
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

// Fallback: if OAuth popup posts completion to opener, redirect to dashboard.
window.addEventListener("message", (e) => {
  try {
    if (e && e.data && e.data.source === "themaestro" && e.data.type === "oauth:completed") {
      window.location.href = "/dashboard"
    }
  } catch (_) {
    // ignore
  }
})
