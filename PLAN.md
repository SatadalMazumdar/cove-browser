# Clove progress

A native Mac browser on WebKit, with Arc-style spaces and profiles. This file tracks what is
built and what is left.

Legend: ✅ done · 🟢 in progress or up next · ⬜ not started

## Overall

`███████████░░░░░░░░░░` 20 / 37 done (54%)

- Foundation: 15 / 15 ✅
- Near-term features: 5 / 11
- Bigger features: 0 / 5
- Distribution and shipping: 0 / 6

## Foundation

- ✅ Spaces and profiles, split apart
- ✅ Sidebar with favorites, pinned tabs, nested folders and today's tabs
- ✅ Drag and drop for tabs, folders and spaces
- ✅ Create, edit, delete and reorder spaces and folders
- ✅ Swipe between spaces with the window tint blending
- ✅ Collapsible pinned area per space
- ✅ Command bar: top-site suggestions, search, keyboard-driven active tabs
- ✅ Tab sleeping with a Settings control
- ✅ Session restore across launches, with a format upgrade
- ✅ Import from Arc: spaces, themes, icons, profiles, favorites, pinned tabs and folders
- ✅ Native full screen with the page edge to edge
- ✅ Floating sidebar with its own window controls and shadow
- ✅ Copy URL at the address bar
- ✅ Clean SF Symbol icon set and the Clove app icon
- ✅ Safari Web Inspector

## Near-term features

- ✅ Ad and tracker blocking, with a Settings toggle
- ✅ Downloads, with a sidebar popover and show-in-Finder
- ✅ Browsing history, feeding the command bar as you type
- ✅ Find on page (Cmd+F)
- ✅ Per-site page zoom (Cmd+plus, minus, 0)
- 🟢 Reader mode: strip a page to clean text
- ⬜ A real new-tab page, instead of only the command bar
- ⬜ Picture in picture and media keys
- ⬜ Per-site block on and off toggle in the URL pill (blocking is global for now)
- ⬜ Arc history and bookmarks import (the history store has a bulk import path, not yet wired to Arc's data)
- ⬜ More settings: default search engine, new-tab behaviour, default theme for new spaces, a global light or dark override

## Bigger features

- ⬜ Mini window for links, Little Arc style (parked on request). A small borderless window with just a URL bar, on the current profile, with a promote-to-tab button. Opened from a modifier-click, a menu item, and as the target for popups.
- ⬜ Passwords and autofill. Unblocked now that the Apple developer license is in hand; still needs a signed, entitled build and a spike of what macOS 27 allows.
- ⬜ Safari web extensions. Needs signing and a packaging flow.
- ⬜ Split view, two pages side by side in one space.
- ⬜ Sync across machines. Needs a backend and end-to-end encryption.

## Distribution and shipping

- ⬜ Code signing and notarization with the Developer ID, hardened runtime and the web view's entitlements
- ⬜ DMG packaging with a drag-to-Applications layout
- ⬜ Sparkle auto-update: an appcast feed, an EdDSA key, and hosting
- ⬜ Full rename and bundle-id migration. The user-facing name is Clove; the internals (bundle id `dev.prototype.cove`, the `Sources/Cove` folder and target, the `Cove/session.json` folder, the drag type id, the `cove-browser` repo) are still Cove. The storage move needs a one-time migration so tabs are not lost. Do this before anyone installs, since the bundle id is permanent after that.
- ⬜ CI on a macOS runner that builds, signs, notarizes and attaches the DMG to a release
- ⬜ Landing page with the logo, a download button and the feature list

## Suggested order

1. Finish the rename and bundle-id migration, while it is cheap.
2. Get Developer ID signing and notarization working end to end.
3. Reader mode, then the new-tab page.
4. The mini window.
5. Picture in picture, more settings.
6. Sparkle auto-update and the CI release pipeline.
7. Passwords and autofill.
8. Landing page and a public launch.

## Notes on the engine

Baked in by using WebKit: no Chrome DevTools or CDP tools, no Widevine DRM (FairPlay only),
and extensions are Safari web extensions rather than Chrome's. These are not bugs to fix,
they are the trade for a small, fast, native app.
