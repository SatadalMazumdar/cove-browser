# Clove

A prototype Mac browser with a sidebar layout, built in Swift on Safari's engine.

Clove is the name. The app is about 5,000 lines of Swift and builds in under a minute.

## What it does

- Sidebar with favorites, pinned tabs, nested folders and today's tabs. The page sits in a rounded card.
- Spaces with their own name, icon, colours and light or dark setting.
- Profiles. A space either gets its own cookies and logins or shares another space's. Favorites belong to the profile.
- Create, edit, delete and reorder spaces. Create, rename and delete folders.
- Drag tabs and folders to reorder them, into folders, onto favorites, or onto another space's icon.
- Import from Arc: spaces, themes, icons, profiles, favorites, pinned tabs, folders and browsing history. Logins and passwords do not come over.
- Two-finger swipe on the sidebar moves between spaces. The window tint blends as you swipe.
- Command bar for search, addresses, history and switching to an open tab, with a keyboard-driven active-tabs view.
- Ad and tracker blocking, global and per site.
- Downloads with progress and show-in-Finder.
- Find on page, reader mode, per-site zoom and picture in picture.
- Settings for tab sleeping, search engine and a light or dark override.
- Background tabs unload after an idle timeout and reload when clicked.
- Tabs, history and scroll position are saved between launches.
- Safari's Web Inspector.

## Build and run

Needs macOS 14 or later and the Xcode Command Line Tools. Xcode itself is not required.

```sh
./build.sh
open build/Clove.app
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
| Ctrl+1 to Ctrl+9 | Jump to a space |
| Cmd+Shift+N | New folder |
| Cmd+Ctrl+N | New space |
| Cmd+Option+I | Web Inspector |

## Known gaps

- No extensions, password manager or split view yet.
- Arc split views import as separate tabs.
- Chrome DevTools and tools built on Chrome's debugging protocol cannot attach, because the engine is WebKit.
- The Web Inspector and the audio check used by tab unloading call private WebKit properties.

## Where things are

- `Sources/Clove/Models.swift` holds tabs, folders, profiles and spaces.
- `Sources/Clove/Store.swift` is the app state: selection, drag and drop rules, spaces, idle unloading.
- `Sources/Clove/Session.swift` reads and writes the session file, and upgrades the older format.
- `Sources/Clove/ArcImport.swift` reads Arc's sidebar file.
- `Sources/Clove/Sidebar.swift` is the sidebar.
- `Sources/Clove/Panels.swift` is the space editor and the import screen.
- `Sources/Clove/ContentView.swift` is the window layout and the page card.
- `Sources/Clove/CommandBar.swift` is the command bar.
- `Sources/Clove/main.swift` is the app start, the menu and the diagnostic flags.

The session is stored at `~/Library/Application Support/Clove/session.json`.

## Licence

MIT. See [LICENSE](LICENSE).
