// The Back button (`CoreComponents.back_link/1`, `data-back`) goes where the
// reader came from when they came by a click inside the site, and up the
// page's own trail when they did not (a link from elsewhere, a new tab, a
// reload of the first page). Its `href` is the trail: what a crawler, a
// middle click and a browser without the Navigation API get.
//
// The Navigation API lists this tab's history entries of this origin,
// contiguous with the current one, so an empty list behind the current entry
// means the reader arrived from outside. Each entry is tagged with the page's
// language as it is entered: a locale switch is a new page in another
// language, and Back must not switch it back. An untagged entry (from before
// this script, or a browser that dropped the state) is not trusted.

const LANG_KEY = "gamend_lang"

// Sign-in pages are a detour, never a place to go back to: walked past.
const AUTH_PATH = /(^|\/)users\/(log_in|register|confirm|settings\/confirm_email)(\/|$)/

export function pathOf(url) {
  if (typeof url !== "string" || url === "") return null
  try {
    const path = new URL(url, "http://x").pathname
    return path.length > 1 ? path.replace(/\/+$/, "") : path
  } catch (_) {
    return null
  }
}

export function isAuthPath(path) {
  return AUTH_PATH.test(path || "")
}

// The entry Back returns to, or null for the page's own trail. `entries` are
// `{key, url, lang}` oldest first, `index` the current one's. Entries of the
// current page (the same path under another query: a game's settings, a
// search) are walked past, so Back leaves the page.
export function backEntry(entries, index, lang) {
  if (!Array.isArray(entries) || !Number.isInteger(index) || index < 1 || index >= entries.length) {
    return null
  }

  const here = pathOf(entries[index]?.url)
  if (here === null) return null

  for (let i = index - 1; i >= 0; i--) {
    const entry = entries[i]
    const path = pathOf(entry?.url)
    if (path === null) return null
    if (path === here || isAuthPath(path)) continue
    return entry.lang === lang ? entry : null
  }

  return null
}

function stateOf(entry) {
  try {
    const state = entry.getState()
    return state && typeof state === "object" ? state : null
  } catch (_) {
    return null
  }
}

export function startBackLink(win = window, doc = document) {
  const nav = win.navigation
  if (!nav || typeof nav.entries !== "function" || typeof nav.traverseTo !== "function") return

  const lang = doc.documentElement.lang || ""

  // Every entry this document enters: the first load, a live navigation's
  // `pushState`, a return to an entry made before.
  const tag = () => {
    const entry = nav.currentEntry
    if (!entry) return
    const state = stateOf(entry)
    if (state && state[LANG_KEY] === lang) return
    try {
      nav.updateCurrentEntry({state: {...(state || {}), [LANG_KEY]: lang}})
    } catch (_) {}
  }

  tag()
  nav.addEventListener("currententrychange", tag)

  // Capture on `window`: ahead of LiveView's own link handler, which would
  // otherwise follow a `navigate` link over the socket.
  win.addEventListener(
    "click",
    (event) => {
      if (event.defaultPrevented || event.button !== 0) return
      if (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return

      const link = event.target && typeof event.target.closest === "function" ? event.target.closest("a[data-back]") : null
      if (!link) return

      const current = nav.currentEntry
      if (!current) return

      const entries = nav.entries().map((entry) => ({
        key: entry.key,
        url: entry.url,
        lang: stateOf(entry)?.[LANG_KEY],
      }))

      const target = backEntry(entries, current.index, lang)
      if (!target) return

      event.preventDefault()
      event.stopPropagation()

      // An entry that cannot be reached any more: the trail, as without this.
      nav.traverseTo(target.key).committed.catch(() => win.location.assign(link.href))
    },
    true,
  )
}
