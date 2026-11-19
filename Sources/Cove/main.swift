import AppKit
import Combine
import SwiftUI
import WebKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    /// Any diagnostic flag runs on the sample tabs, apart from the session file. COVE_SESSION_FILE opts back in.
    private let store = BrowserStore(
        persist: !CommandLine.arguments.dropFirst().contains { $0.hasPrefix("--") }
            || ProcessInfo.processInfo.environment["COVE_SESSION_FILE"] != nil
    )
    private var window: NSWindow!
    private var bag = Set<AnyCancellable>()
    private var probe: WKWebView?

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1320, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.minSize = NSSize(width: 720, height: 480)
        // So the store's mouse monitor keeps getting moves while the pointer is over a web view,
        // which is how the floating sidebar knows to close.
        window.acceptsMouseMovedEvents = true
        window.contentView = NSHostingView(rootView: ContentView(store: store))
        window.setFrameAutosaveName("CoveMainWindow")
        if window.frame.origin == .zero { window.center() }
        window.delegate = self
        // Let the green button and Enter Full Screen use the system full screen, which gives the
        // window its own Space. fullScreenPrimary is what makes that work for a custom titlebar.
        window.collectionBehavior = [.fullScreenPrimary]
        store.window = window

        // The traffic lights live in the sidebar, so they go away with it.
        store.$sidebarVisible.sink { [weak self] visible in
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                self?.window.standardWindowButton(kind)?.isHidden = !visible
            }
        }.store(in: &bag)

        // Space names and order show in the menu bar, so it follows them.
        store.$revision.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { NSApp.mainMenu = self?.buildMenu() }
        }.store(in: &bag)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let args = CommandLine.arguments
        if let flag = args.firstIndex(of: "--url"), args.indices.contains(flag + 1),
           let url = URL(string: args[flag + 1]) {
            store.newTab(url: url)
        }
        // Someone arriving from Arc sees the import offer before the sample tabs.
        if store.startedFromSeed, store.persist, ArcImport.isAvailable {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.store.openArcImport() }
        }
        if args.contains("--arc-check") { runArcCheck(apply: args.contains("--apply")) }
        if args.contains("--move-check") { runMoveCheck() }
        if let flag = args.firstIndex(of: "--panel"), args.indices.contains(flag + 1) {
            switch args[flag + 1] {
            case "new": store.openSpaceEditor()
            case "edit": store.openSpaceEditor(editing: store.space)
            case "settings": store.openSettings()
            default: store.openArcImport()
            }
        }
        if args.contains("--peek") {
            store.sidebarVisible = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.store.peeking = true }
        }
        if args.contains("--idle-check") {
            // Opens three more tabs, returns to the first, then reports how many pages stay loaded.
            window.ignoresMouseEvents = true
            let first = store.selectedTab
            let extras = store.space.pinned.flatMap(\.tabs).prefix(2) + store.space.today.dropFirst()
            extras.forEach { store.select($0) }
            if let first { store.select(first) }
            print("loaded at start:", store.loadedTabCount)
            DispatchQueue.main.asyncAfter(deadline: .now() + 14) {
                print("loaded after idle limit:", self.store.loadedTabCount)
                if let back = extras.first {
                    self.store.select(back)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        print("reselected tab reloaded:", back.webView != nil, back.url.absoluteString)
                        exit(0)
                    }
                }
            }
        }
        if args.contains("--block-check") {
            window.ignoresMouseEvents = true
            // The store already kicked off prepare(); just check the shared list got populated.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                let ready = ContentBlocker.shared.ruleList != nil
                print("blocklist ready:", ready, "enabled:", ContentBlocker.shared.enabled)
                exit(ready ? 0 : 1)
            }
        }
        if args.contains("--download-check") {
            window.ignoresMouseEvents = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                guard let wv = self.store.selectedTab?.webView else { print("no web view"); exit(1) }
                wv.startDownload(using: URLRequest(url: URL(string: "https://example.com/")!)) { download in
                    self.store.downloads.register(download)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                    let item = self.store.downloads.items.first
                    let exists = item?.fileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
                    print("download state:", String(describing: item?.state), "file saved:", exists, item?.filename ?? "")
                    if let url = item?.fileURL { try? FileManager.default.removeItem(at: url) }  // clean up the test file
                    exit(exists ? 0 : 1)
                }
            }
        }
        if args.contains("--history-check") {
            window.ignoresMouseEvents = true
            let pid = store.space.profile.id
            store.history.record(url: URL(string: "https://developer.mozilla.org/en-US/docs/Web")!,
                                 title: "MDN Web Docs", host: "developer.mozilla.org", profile: pid)
            store.history.record(url: URL(string: "https://developer.mozilla.org/en-US/docs/Web")!,
                                 title: "MDN Web Docs", host: "developer.mozilla.org", profile: pid)
            store.history.record(url: URL(string: "https://news.ycombinator.com/")!,
                                 title: "Hacker News", host: "news.ycombinator.com", profile: pid)
            let hits = store.history.matches("mdn", profile: pid)
            print("history hits for 'mdn':", hits.count, hits.first.map { "\($0.title) ×\($0.count)" } ?? "")
            let web = store.history.matches("developer", profile: pid)
            print("history hits for 'developer':", web.count)
            exit(hits.count == 1 && hits.first?.count == 2 ? 0 : 1)
        }
        if args.contains("--drm-check") { runDRMCheck() }
        if args.contains("--inspector-check") {
            window.ignoresMouseEvents = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                self.toggleInspector()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    let found = self.store.selectedTab?.webView.flatMap { self.inspector(for: $0) }
                    print("inspector visible:", found?.value(forKey: "isVisible") ?? "not found")
                    exit(0)
                }
            }
        }
        if let flag = args.firstIndex(of: "--snapshot"), args.indices.contains(flag + 1) {
            let path = args[flag + 1]
            window.ignoresMouseEvents = true
            if args.contains("--command-bar") { store.openCommandBar(.newTab) }
            if args.contains("--find") { store.openFind(); store.findQuery = "the" }
            if let page = args.firstIndex(of: "--page"), args.indices.contains(page + 1),
               let position = Double(args[page + 1]) {
                store.pagePosition = position
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { self.snapshot(to: path) }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
    }

    // The page runs edge to edge in full screen and keeps its gutter in a window.
    func windowDidEnterFullScreen(_ notification: Notification) { store.fullScreen = true }
    func windowDidExitFullScreen(_ notification: Notification) { store.fullScreen = false }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: Menu

    private func buildMenu() -> NSMenu {
        let main = NSMenu()

        func menu(_ title: String, _ items: [NSMenuItem]) {
            let holder = NSMenuItem()
            let submenu = NSMenu(title: title)
            items.forEach { submenu.addItem($0) }
            holder.submenu = submenu
            main.addItem(holder)
        }
        func item(_ title: String, _ action: Selector?, _ key: String = "",
                  _ mods: NSEvent.ModifierFlags = .command, tag: Int = 0) -> NSMenuItem {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
            entry.keyEquivalentModifierMask = mods
            entry.tag = tag
            if let action, responds(to: action) { entry.target = self }
            return entry
        }
        let up = String(UnicodeScalar(NSUpArrowFunctionKey)!)
        let down = String(UnicodeScalar(NSDownArrowFunctionKey)!)

        menu("Clove", [
            item("About Clove", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Settings...", #selector(openSettings), ","),
            .separator(),
            item("Hide Clove", #selector(NSApplication.hide(_:)), "h"),
            item("Quit Clove", #selector(NSApplication.terminate(_:)), "q"),
        ])
        menu("File", [
            item("New Tab", #selector(newTab), "t"),
            item("Open Location", #selector(openLocation), "l"),
            .separator(),
            item("New Folder", #selector(newFolder), "n", [.command, .shift]),
            item("New Space...", #selector(newSpace), "n", [.command, .control]),
            item("Import from Arc...", #selector(importFromArc)),
            .separator(),
            item("Close Tab", #selector(closeTab), "w"),
        ])
        menu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item("Copy URL", #selector(copyURL), "c", [.command, .shift]),
        ])
        menu("View", [
            item("Toggle Sidebar", #selector(toggleSidebar), "s"),
            .separator(),
            item("Find on Page", #selector(findOnPage), "f"),
            .separator(),
            item("Zoom In", #selector(zoomIn), "="),
            item("Zoom Out", #selector(zoomOut), "-"),
            item("Actual Size", #selector(zoomReset), "0"),
            .separator(),
            item("Reload", #selector(reload), "r"),
            item("Back", #selector(goBack), "["),
            item("Forward", #selector(goForward), "]"),
            .separator(),
            item("Toggle Web Inspector", #selector(toggleInspector), "i", [.command, .option]),
            .separator(),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ])
        menu("Tabs", [
            item("Next Tab", #selector(nextTab), down, [.command, .option]),
            item("Previous Tab", #selector(previousTab), up, [.command, .option]),
            .separator(),
            item("Pin or Unpin Tab", #selector(togglePin), "d"),
        ])
        let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
        let right = String(UnicodeScalar(NSRightArrowFunctionKey)!)
        menu("Spaces", [
            item("Next Space", #selector(nextSpace), right, [.command, .option]),
            item("Previous Space", #selector(previousSpace), left, [.command, .option]),
            .separator(),
            item("Edit Space...", #selector(editSpace)),
            item("Delete Space...", #selector(deleteSpace)),
            .separator(),
        ] + store.spaces.enumerated().map { index, space in
            item(space.name, #selector(switchSpace(_:)), index < 9 ? "\(index + 1)" : "", .control, tag: index)
        })
        menu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
        ])
        return main
    }

    @objc private func newTab() { store.openCommandBar(.newTab) }
    @objc private func openLocation() { store.openCommandBar(.editURL) }
    @objc private func closeTab() { store.closeSelected() }
    @objc private func copyURL() { store.copyURL() }
    @objc private func toggleSidebar() { store.sidebarVisible.toggle() }
    @objc private func findOnPage() { store.openFind() }
    @objc private func zoomIn() { store.changeZoom(1) }
    @objc private func zoomOut() { store.changeZoom(-1) }
    @objc private func zoomReset() { store.changeZoom(0) }
    @objc private func reload() { store.selectedTab?.webView?.reload() }
    @objc private func goBack() { store.selectedTab?.webView?.goBack() }
    @objc private func goForward() { store.selectedTab?.webView?.goForward() }
    @objc private func nextTab() { store.cycle(1) }
    @objc private func previousTab() { store.cycle(-1) }
    @objc private func togglePin() { if let tab = store.selectedTab { store.togglePin(tab) } }
    @objc private func switchSpace(_ sender: NSMenuItem) { store.switchSpace(to: sender.tag) }
    @objc private func newFolder() { store.newFolder() }
    @objc private func newSpace() { store.openSpaceEditor() }
    @objc private func editSpace() { store.openSpaceEditor(editing: store.space) }
    @objc private func deleteSpace() { store.confirmDelete(store.space) }
    @objc private func importFromArc() { store.openArcImport() }
    @objc private func openSettings() { store.openSettings() }
    @objc private func nextSpace() { store.stepSpace(1) }
    @objc private func previousSpace() { store.stepSpace(-1) }

    /// WebKit keeps its inspector behind a private property. There is no public way to open it from code.
    private func inspector(for webView: WKWebView) -> NSObject? {
        let getter = NSSelectorFromString("_inspector")
        guard webView.responds(to: getter) else { return nil }
        return webView.perform(getter)?.takeUnretainedValue() as? NSObject
    }

    @objc private func toggleInspector() {
        guard let webView = store.selectedTab?.webView, let inspector = inspector(for: webView) else { return }
        let visible = (inspector.value(forKey: "isVisible") as? Bool) ?? false
        let action = NSSelectorFromString(visible ? "close" : "show")
        if inspector.responds(to: action) { inspector.perform(action) }
    }

    // MARK: Diagnostics

    /// `--drm-check` asks the engine which DRM key systems it offers, prints the answer, and quits.
    private func runDRMCheck() {
        let webView = WKWebView(frame: .zero, configuration: store.space.profile.makeConfiguration())
        probe = webView
        webView.loadHTMLString("<!doctype html><title>probe</title>", baseURL: URL(string: "https://example.com/"))
        let js = """
        const video = 'video/mp4; codecs="avc1.42E01E"';
        const configs = ['sinf', 'cenc', 'skd', 'keyids'].map(t => ({
            initDataTypes: [t], videoCapabilities: [{ contentType: video }]
        }));
        const out = { secureContext: window.isSecureContext, userAgent: navigator.userAgent };
        out.getUserMedia = typeof navigator.mediaDevices?.getUserMedia;
        out.getDisplayMedia = typeof navigator.mediaDevices?.getDisplayMedia;
        out.RTCPeerConnection = typeof RTCPeerConnection;
        try { out.devices = (await navigator.mediaDevices.enumerateDevices()).map(d => d.kind).join(','); }
        catch (error) { out.devices = 'error ' + error.name; }
        for (const system of ['com.apple.fps', 'com.apple.fps.1_0', 'com.widevine.alpha', 'org.w3.clearkey']) {
            try {
                const access = await navigator.requestMediaKeySystemAccess(system, configs);
                out[system] = 'available, initDataTypes=' + access.getConfiguration().initDataTypes.join(',');
            } catch (error) {
                out[system] = 'unavailable (' + error.name + ')';
            }
        }
        return JSON.stringify(out, null, 2);
        """
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { result in
                switch result {
                case .success(let value): print(value)
                case .failure(let error): print("probe failed: \(error)")
                }
                exit(0)
            }
        }
    }

    /// `--arc-check` reads Arc's sidebar and prints counts only, never titles or addresses.
    /// With `--apply` it also loads the result into this window, replacing the sample spaces.
    private func runArcCheck(apply: Bool) {
        do {
            let plan = try ArcImport.read()
            for profile in plan.profiles {
                print("profile:", profile.favorites.count, "favorites")
            }
            for space in plan.spaces {
                print("space:", space.pinnedTabCount, "pinned,", space.folderCount, "folders,", space.today.count,
                      "open, icon", space.icon, "hue", (space.theme.hue * 100).rounded() / 100,
                      "intensity", (space.theme.intensity * 100).rounded() / 100, space.theme.mode.rawValue)
            }
            if apply {
                store.apply(plan, options: ArcImportOptions(chosen: Set(plan.spaces.indices), replaceExisting: true))
                print("after import:", store.spaces.count, "spaces,", store.profiles.count, "profiles,",
                      store.everyTab.count, "tabs,", store.loadedTabCount, "loaded")
            } else {
                exit(0)
            }
        } catch {
            print("arc check failed:", error.localizedDescription)
            exit(1)
        }
    }

    /// `--move-check` runs the drag and drop rules on the sample tabs and prints what failed.
    private func runMoveCheck() {
        window.ignoresMouseEvents = true
        var failures = 0
        func expect(_ label: String, _ condition: Bool) {
            if !condition { failures += 1 }
            print(condition ? "ok  " : "FAIL", label)
        }
        let personal = store.spaces[0], work = store.spaces[1]
        guard case .tab(let hackerNews) = personal.pinned[0], case .folder(let reading) = personal.pinned[2] else {
            print("FAIL sample tabs changed shape")
            exit(1)
        }
        let wikipedia = personal.today[0], apple = personal.today[1]

        store.drop(.node(apple.id), on: .before(wikipedia.id))
        expect("reorder inside today", personal.today.first === apple)
        store.drop(.node(apple.id), on: .intoFolder(reading.id))
        expect("today tab into a folder", reading.children.last?.id == apple.id && personal.today.count == 1)
        store.drop(.node(reading.id), on: .before(hackerNews.id))
        expect("folder to the top of pinned", personal.pinned.first?.id == reading.id)
        expect("folder refuses today", !store.drop(.node(reading.id), on: .todayStart(space: personal.id)))
        expect("folder refuses itself", !store.drop(.node(reading.id), on: .intoFolder(reading.id)))
        store.drop(.node(hackerNews.id), on: .favoritesEnd(profile: personal.profile.id))
        expect("pinned tab to favorites", personal.profile.favorites.last === hackerNews && store.isFavorite(hackerNews))
        store.togglePin(hackerNews)
        expect("favorite back to pinned", personal.pinned.last?.id == hackerNews.id)

        let before = wikipedia.webView != nil
        store.drop(.node(wikipedia.id), on: .space(work.id))
        expect("tab to another space", work.today.first === wikipedia && wikipedia.profile === work.profile)
        expect("page dropped on profile change", before && wikipedia.webView == nil)
        expect("old space picked another tab", personal.selected != nil && personal.selected !== wikipedia)

        store.drop(.space(work.id), on: .space(personal.id))
        expect("space reorder keeps the current space", store.spaces.first === work && store.space === personal)

        let shared = store.addSpace(name: "Shared", icon: "🧪", theme: SpaceTheme(hue: 0.1), sharing: personal.profile)
        expect("shared space uses the same profile", shared.profile === personal.profile && store.profiles.count == 2)
        expect("shared space shows the profile's favorites", shared.allTabs.count == personal.profile.favorites.count)
        let fresh = store.addSpace(name: "Fresh", icon: "🚀", theme: SpaceTheme(), sharing: nil)
        expect("new profile created", store.profiles.count == 3 && fresh.profile !== personal.profile)
        store.delete(fresh, eraseProfile: true)
        expect("delete with erase removes the profile", store.profiles.count == 2 && store.spaces.count == 3)
        store.delete(reading)
        expect("deleting a folder keeps its tabs", personal.folders.isEmpty && personal.pinned.contains { $0.id == apple.id })

        print(failures == 0 ? "all checks passed" : "\(failures) checks failed")
        exit(failures == 0 ? 0 : 1)
    }

    /// `--snapshot <path>` writes a PNG of the window and quits. Used to check layout without a human.
    private func snapshot(to path: String) {
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
        view.cacheDisplay(in: view.bounds, to: rep)

        func write(_ web: NSImage?, _ frame: NSRect) {
            let image = NSImage(size: view.bounds.size)
            image.lockFocus()
            if let web, store.commandBar == nil, store.panel == nil, !store.peeking {
                rep.draw(in: view.bounds)
                web.draw(in: frame)
            } else {
                rep.draw(in: view.bounds)
            }
            image.unlockFocus()
            if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
               let png = bitmap.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: path))
            }
            exit(0)
        }

        if let webView = store.selectedTab?.webView {
            var frame = webView.convert(webView.bounds, to: view)
            if view.isFlipped { frame.origin.y = view.bounds.height - frame.maxY }
            webView.takeSnapshot(with: nil) { image, _ in write(image, frame) }
        } else {
            write(nil, .zero)
        }
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
