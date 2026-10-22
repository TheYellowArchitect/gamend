// What the navbar has room for, measured rather than guessed from a
// breakpoint (2026-10-21, user): its links spelled out, then as icons, then
// without the reader's name, then the menu. How wide a bar is depends on the
// host's links, the language's words and the reader's name and balance, so
// no width fits every site.
//
// `<html data-nav>` names what shows, and each word is a class's condition
// (`HostLayoutNavigation`): `bar` the links in the bar, `labels` their words,
// `name` the reader's name. Each stage's width is measured once the page is
// drawn and kept per language, so the next page's `theme-init.js` sets the
// stage before its first paint, and a resize only compares numbers.

export const STAGES = [
  ["full", "bar labels name"],
  ["icons", "bar name"],
  ["avatar", "bar"],
]

export const MENU = "menu"

// The bar from this width while nothing is measured: the `xl` breakpoint it
// had before it was measured.
export const UNMEASURED_BAR = 1280

const KEY = "gamend:nav"

// The first stage whose width fits, else the menu.
export function stageFor(needs, width) {
  if (!needs) return width >= UNMEASURED_BAR ? STAGES[0][1] : MENU
  for (const [name, words] of STAGES) {
    if (needs[name] <= width) return words
  }
  return MENU
}

function readSaved(lang) {
  try {
    return JSON.parse(localStorage.getItem(KEY) || "{}")[lang] || null
  } catch (_) {
    return null
  }
}

function save(lang, needs) {
  try {
    const saved = JSON.parse(localStorage.getItem(KEY) || "{}")
    saved[lang] = needs
    localStorage.setItem(KEY, JSON.stringify(saved))
  } catch (_) {
    // A browser that keeps nothing measures again on every page.
  }
}

// With the sidebar (`<html data-side-nav>`) there is none on a phone, so a
// phone's width is the menu whatever else would fit: the sidebar's links are
// the menu's there.
function sidePhone() {
  const root = document.documentElement
  return (
    root.hasAttribute?.("data-side-nav") === true &&
    typeof matchMedia === "function" &&
    !matchMedia("(min-width: 48rem)").matches
  )
}

function apply(words) {
  const root = document.documentElement
  if (sidePhone()) words = MENU
  if (root.dataset.nav !== words) root.dataset.nav = words
}

// Before the first paint (`theme-init.js`): the page has no header yet, and
// the root's width is the window's.
export function applySaved() {
  const root = document.documentElement
  apply(stageFor(readSaved(root.lang), root.clientWidth))
}

// Each stage's width: the header's padding and gap, the logo with its name on
// one line, and the bar. The logo's room is widened while it is measured, so
// the name neither wraps nor turns to screen-reader text (`@max-[8rem]`).
export function measure(header) {
  const logo = header.querySelector("[data-nav-logo]")
  const bar = header.querySelector("[data-nav-bar]")
  if (!logo || !bar) return null

  const root = document.documentElement
  const before = root.dataset.nav
  const room = logo.parentElement
  room.style.flex = "none"
  room.style.width = "100vw"

  const needs = {}
  for (const [name, words] of STAGES) {
    root.dataset.nav = words
    const style = getComputedStyle(header)
    const gap = parseFloat(style.columnGap) || 0
    const padding = parseFloat(style.paddingLeft) + parseFloat(style.paddingRight)
    const width = logo.getBoundingClientRect().width + bar.getBoundingClientRect().width
    needs[name] = Math.ceil(padding + gap + width)
  }

  room.style.flex = ""
  room.style.width = ""
  if (before === undefined) delete root.dataset.nav
  else root.dataset.nav = before
  return needs
}

const fitted = new WeakMap()

// Measures `header` now, again when its width, its fonts or its content
// change (`refit`, from the navbar's hook), and sets the stage that fits.
export function startNavbarFit(header) {
  if (!header) return null
  if (fitted.has(header)) return fitted.get(header)

  const lang = document.documentElement.lang
  let needs = readSaved(lang)
  let width = null

  const refit = () => {
    needs = measure(header) || needs
    if (needs) save(lang, needs)
    width = header.clientWidth
    apply(stageFor(needs, width))
  }

  // Only a change of width: a stage that changes the header's height must
  // not measure it again.
  const observer = new ResizeObserver(() => {
    if (header.clientWidth !== width) refit()
  })
  observer.observe(header)
  document.fonts?.ready.then(refit)

  const stop = () => {
    observer.disconnect()
    fitted.delete(header)
  }

  const fit = {refit, stop}
  fitted.set(header, fit)
  return fit
}
