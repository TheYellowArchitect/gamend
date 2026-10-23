// The sidebar's state (`HostLayoutNavigation.side_nav/1`): `<html
// data-side="rail">` where the reader collapsed it. This browser keeps it, as
// it keeps the theme, and `theme-init.js` sets it again before the next page
// paints, so a page never draws the sidebar open and then folds it.

const KEY = "gamend:side"

export function applySavedSide() {
  try {
    if (localStorage.getItem(KEY) === "rail") document.documentElement.dataset.side = "rail"
  } catch (_) {
    // A browser that keeps nothing opens it on every page.
  }
}

export function toggleSide(root = document.documentElement) {
  const rail = root.dataset.side !== "rail"
  if (rail) root.dataset.side = "rail"
  else delete root.dataset.side

  try {
    localStorage.setItem(KEY, rail ? "rail" : "open")
  } catch (_) {
    // Kept for this page only.
  }
  // The auto layout's bar fits again beside it (`navbar_fit.js`).
  document.dispatchEvent?.(new CustomEvent("gamend:side"))
  return rail
}

// On `document`, not on the button: the sidebar is drawn again with the
// page, and a listener bound to its button would go with it.
export function startSideNav() {
  document.addEventListener("click", (event) => {
    if (event.target.closest?.("[data-side-toggle]")) toggleSide()
  })
}
