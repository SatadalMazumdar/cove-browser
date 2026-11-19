# Cove

A prototype Mac browser with a sidebar layout, built in Swift on Safari's engine.

Cove is a working name. The app is about 1,800 lines of Swift and builds in under a minute.

## What it does

- Sidebar with favorites, pinned tabs, folders and today's tabs. The page sits in a rounded card.
- Spaces, each with its own profile. Cookies and logins never cross between spaces.
- Two-finger swipe on the sidebar moves between spaces. The window tint blends as you swipe.
- Command bar for search, addresses and switching to an open tab.
- Background tabs unload after 10 minutes idle and reload when clicked.
- Tabs, history and scroll position are saved between launches.
- Safari's Web Inspector.

## Build and run

Needs macOS 14 or later and the Xcode Command Line Tools. Xcode itself is not required.

```sh
./build.sh
open build/Cove.app
```

## Shortcuts

| Keys | Action |
|---|---|
| Cmd+T | New tab |
| Cmd+L | Edit the current address |
| Cmd+W | Close tab |
| Cmd+S | Show or hide the sidebar |
| Cmd+D | Pin or unpin tab |
| Cmd+Shift+C | Copy the page address |
| Cmd+Option+Up, Down | Previous or next tab |
| Cmd+Option+Left, Right | Previous or next space |
| Ctrl+1, Ctrl+2 | Jump to a space |
| Cmd+Option+I | Web Inspector |

## Known gaps

- No extensions, downloads, history view, password manager or split view.
- No drag to reorder tabs.
- Chrome DevTools and tools built on Chrome's debugging protocol cannot attach, because the engine is WebKit.
- The Web Inspector and the audio check used by tab unloading call private WebKit properties.

## Where things are

- `Sources/Cove/Models.swift` holds tabs, spaces, profiles, idle unloading and the session file.
- `Sources/Cove/Sidebar.swift` is the sidebar.
- `Sources/Cove/ContentView.swift` is the window layout and the page card.
- `Sources/Cove/CommandBar.swift` is the command bar.
- `Sources/Cove/main.swift` is the app start, the menu and the diagnostic flags.

The session is stored at `~/Library/Application Support/Cove/session.json`.

## Licence

MIT. See [LICENSE](LICENSE).
