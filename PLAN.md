# Clove progress

A native Mac browser on WebKit, with Arc-style spaces and profiles. This file tracks what is
built and what is left.

Legend: ✅ done · 🟢 in progress or up next · ⬜ not started

## Overall

`█████████████████░░░` 31 / 36 done (86%)

- Foundation: 15 / 15 ✅
- Near-term features: 10 / 10 ✅
- Bigger features: 5 / 5 ✅
- Distribution and shipping: 1 / 6

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
- ✅ Arc history import, feeding the command bar (bookmarks come over as pinned tabs and favorites)
- ✅ Reader mode: strip a page to clean text
- ✅ Per-site block on and off toggle in the URL pill
- ✅ More settings: default search engine and a global light or dark override
- ✅ Picture in picture, and media keys through WebKit's Now Playing

## Bigger features

- ✅ Mini window for links, Little Arc style. Option-click a link, or Cmd+Shift+O, opens a small floating window on the current profile with a promote-to-tab button.
- ✅ Passwords and autofill. Clove's own keychain store, with a script that offers to save on login and fills on return. A Developer ID signed build makes the keychain access prompt-free.
- ✅ Extensions, as userscripts: custom JS per site, managed in a panel. Full Safari web extensions need an Xcode app-extension target and signing, which the Command Line Tools build cannot produce, so this is the buildable stand-in.
- ✅ Split view, two pages side by side in one space.
- ✅ Sync, via the session file in iCloud Drive, newer-wins. Real CloudKit sync needs entitlements and a container; this is what an unsigned build can do. History and passwords do not sync.

## Distribution and shipping

- ⬜ Code signing and notarization with the Developer ID, hardened runtime and the web view's entitlements
- ⬜ DMG packaging with a drag-to-Applications layout
- ⬜ Sparkle auto-update: an appcast feed, an EdDSA key, and hosting
- ✅ Full rename and bundle-id migration. Everything internal is Clove now, the bundle id is `dev.clove.browser`, and a first-launch migration copies the old Cove app data plus the WebKit and cookie stores so tabs, history and logins carry over. The GitHub repo is still named `cove-browser`; renaming it is a separate step whenever you want the URL changed.
- ⬜ CI on a macOS runner that builds, signs, notarizes and attaches the DMG to a release
- ⬜ Landing page with the logo, a download button and the feature list

## Suggested order

1. Finish the rename and bundle-id migration, while it is cheap.
2. Get Developer ID signing and notarization working end to end.
3. Reader mode.
4. The mini window.
5. Picture in picture, more settings.
6. Sparkle auto-update and the CI release pipeline.
7. Passwords and autofill.
8. Landing page and a public launch.

## Notes on the engine

Baked in by using WebKit: no Chrome DevTools or CDP tools, no Widevine DRM (FairPlay only),
and extensions are Safari web extensions rather than Chrome's. These are not bugs to fix,
they are the trade for a small, fast, native app.
