# Clove plan

A native Mac browser on WebKit, with Arc-style spaces and profiles. This is the working
plan: what exists, what to build next, and what shipping needs. Ordered by priority.

## Where it stands

Done and in the app today:

- Spaces and profiles, split apart. A space has a name, icon, colours and light or dark
  setting. A profile is a cookie and login jar; several spaces can share one. Favorites
  belong to the profile.
- Sidebar with favorites, pinned tabs, nested folders and today's tabs. Drag to reorder,
  into folders, onto favorites, onto another space.
- Create, edit, delete and reorder spaces and folders.
- Swipe between spaces with the window tint blending.
- Collapsible pinned area per space.
- Command bar: top-site suggestions, search, and an Active Tabs command that opens a
  keyboard-driven sub-view (arrows move, Return switches, Cmd+Return sleeps, Cmd+Delete closes).
- Tab sleeping after an idle timeout, with a Settings control and a sleep-now action.
- Session restore across launches, with a format upgrade from the old file.
- Import from Arc: spaces, themes, icons, profiles, favorites, pinned tabs and folders.
- Native full screen that gives the window its own desktop; the page runs edge to edge
  there and keeps its gutter in a window.
- Floating sidebar on the left edge when the sidebar is hidden, with its own window controls
  and a shadow that draws over the page.
- Copy URL at the address bar.
- Clean SF Symbol icon set, no emoji.
- App icon and the Clove name.
- Safari Web Inspector.

Known gaps baked in by the engine choice: no Chrome DevTools or CDP tools (the engine is
WebKit), no Widevine DRM (FairPlay only), no extensions yet.

## P0, build as soon as possible

The things that make it a browser people can live in.

1. Ad and tracker blocking. WebKit has a native content blocker that takes EasyList and
   EasyPrivacy filter lists, compiled once and attached to every page. Add a per-site
   on and off switch in the URL pill. Caveat: rule lists cannot run scripts, so this stops
   most display ads and trackers but will not match uBlock Origin on YouTube.
2. Downloads. A `WKDownloadDelegate` that saves to the Downloads folder, with a small list
   in the sidebar footer showing progress and a reveal-in-Finder button.
3. History. A per-profile SQLite store of url, title, visit count and last visit. The
   command bar ranks matches from it by frequency and recency, alongside open tabs. Arc
   history imports into the same table so suggestions work from the first launch.
4. Mini window for a single link. See the section below. High want from the owner.
5. Find in page. Cmd+F with highlight and next or previous.

## P1, next

6. Reader mode and per-site zoom that sticks.
7. A real new-tab page, instead of the command bar only.
8. Picture in picture and media keys.
9. More settings: default search engine, new-tab behaviour, restore-on-launch toggle,
   default theme for new spaces, a global light or dark override.
10. Passwords and autofill. The honest version is hard. Safari autofill is restricted in a
    third-party web view and needs a paid Apple developer account and a signed, entitled
    build. Spike what macOS 27 allows before committing to a design. Passwords already live
    in the Apple Passwords app after the earlier Arc export, so this is about surfacing them.

## P2, bigger bets

11. Safari web extensions. WebKit supports them, but packaging and loading is a real project
    and needs signing.
12. Split view, two pages side by side in one space.
13. Sync across machines. Needs a backend and end-to-end encryption. Large.
14. A compact, sidebar-less mode and a command palette for actions, not just URLs.

## Mini window for links (Little Arc style)

The request: when a link would open a new window, or when the owner wants a quick look,
open it in a small floating window with just a URL bar and the page, not a full profile
window with the whole sidebar. Close it and it is gone, or promote it into a real tab.

Why it is not wired yet: today a `window.open` or a target=_blank link lands in a new tab
in the current space. Real popups that ask for a separate window are not handled as their
own window, which is the "a new window pops up" fighting the owner saw. Parked on purpose
until the design is settled.

Design when we build it:

- A borderless `NSWindow`, smaller than the main one, centred or near the pointer, holding
  one `WKWebView` and a slim address bar. No sidebar, no spaces.
- It uses the current space's profile, so the viewer is already signed in.
- A button to promote the page into a real tab in the current space, and plain close.
- Opened from: a modifier-click on a link, a menu item, and as the target for popups and
  target=_blank when the owner opts into that instead of a new tab.
- One mini window reused for quick looks, so links do not stack up a pile of windows.

## Distribution, the real blocker for a public build

Right now the build is ad-hoc signed, so anyone who downloads it hits Gatekeeper's "Clove
can't be opened."

- Apple Developer Program membership, 99 USD a year.
- A Developer ID Application certificate; sign with the hardened runtime and the entitlements
  the web view needs (JIT, network client, camera and microphone).
- Notarize with Apple and staple the ticket.
- This also unlocks the passwords and autofill work.
- Package as a DMG with a drag-to-Applications layout.
- Auto-update with Sparkle: an appcast feed, an EdDSA signing key, and hosting for the feed
  and the builds.
- Version and build numbers driven from `build.sh` instead of the hardcoded 0.1.

## The rename, done properly

The user-facing name is Clove, but the internals are still Cove so the saved session did not
move. Before any public install, finish it once: the bundle id (`dev.prototype.cove`), the
`Sources/Cove` folder and SwiftPM target, the Application Support folder (`Cove/session.json`),
the drag type id, and the GitHub repo (`cove-browser`). The storage-folder move needs a
one-time migration so existing tabs are not lost. The bundle id is permanent once people
install, so change it first.

## Project hygiene

- CI on a macOS runner that builds, signs, notarizes and attaches the DMG to a release.
- README with screenshots; CONTRIBUTING; the MIT licence is already in.
- Brand colours pulled from the logo applied to the default theme and a landing page.
- A simple landing page with the logo, a download button and the feature list.

## Suggested order

1. Finish the rename and bundle-id migration now, while it is cheap.
2. Get Developer ID signing and notarization working end to end, so there is a distributable
   build at all.
3. Ad and tracker blocking, then downloads, then history.
4. The mini window.
5. Find in page, reader mode.
6. Sparkle auto-update and the CI release pipeline.
7. The passwords spike.
8. Landing page and a public launch.
