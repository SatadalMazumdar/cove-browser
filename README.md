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

## Releasing

`build.sh` signs with a Developer ID Application certificate when the keychain has one, and falls
back to an ad hoc signature when it does not.

To cut a release:

1. Bump `VERSION`, commit, and push.
2. Tag it: `git tag v$(cat VERSION) && git push --tags`.

The Release workflow then builds, signs, notarizes, packs the DMG, signs it for Sparkle, and
publishes a GitHub release with the DMG and `appcast.xml`. Installed copies find the update
through that appcast.

The workflow reads six repository secrets: `DEVELOPER_ID_P12` (the certificate, base64),
`DEVELOPER_ID_P12_PASSWORD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_PASSWORD` (an app-specific
password), and `SPARKLE_PRIVATE_KEY`.

To build a release on your own Mac, store the notary login once, then run the script:

```sh
xcrun notarytool store-credentials clove-notary --apple-id <id> --team-id <team> --password <app-specific>
scripts/release.sh
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
