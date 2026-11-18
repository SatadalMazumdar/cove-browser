import AppKit
import Combine
import SwiftUI
import WebKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
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
        window.contentView = NSHostingView(rootView: ContentView(store: store))
        window.setFrameAutosaveName("CoveMainWindow")
        if window.frame.origin == .zero { window.center() }
        store.window = window

        // The traffic lights live in the sidebar, so they go away with it.
        store.$sidebarVisible.sink { [weak self] visible in
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                self?.window.standardWindowButton(kind)?.isHidden = !visible
            }
        }.store(in: &bag)

        NSApp.mainMenu = buildMenu()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let args = CommandLine.arguments
        if let flag = args.firstIndex(of: "--url"), args.indices.contains(flag + 1),
           let url = URL(string: args[flag + 1]) {
            store.newTab(url: url)
        }
        if args.contains("--peek") {
            store.sidebarVisible = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.store.peeking = true }
        }
        if args.contains("--idle-check") {
            // Opens three more tabs, returns to the first, then reports how many pages stay loaded.
            window.ignoresMouseEvents = true
            let first = store.selectedTab
            let extras = store.space.pinned + store.space.today.dropFirst()
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

        menu("Cove", [
            item("About Cove", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Hide Cove", #selector(NSApplication.hide(_:)), "h"),
            item("Quit Cove", #selector(NSApplication.terminate(_:)), "q"),
        ])
        menu("File", [
            item("New Tab", #selector(newTab), "t"),
            item("Open Location", #selector(openLocation), "l"),
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
        ] + store.spaces.enumerated().map { index, space in
            item(space.name, #selector(switchSpace(_:)), "\(index + 1)", .control, tag: index)
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
    @objc private func reload() { store.selectedTab?.webView?.reload() }
    @objc private func goBack() { store.selectedTab?.webView?.goBack() }
    @objc private func goForward() { store.selectedTab?.webView?.goForward() }
    @objc private func nextTab() { store.cycle(1) }
    @objc private func previousTab() { store.cycle(-1) }
    @objc private func togglePin() { if let tab = store.selectedTab { store.togglePin(tab) } }
    @objc private func switchSpace(_ sender: NSMenuItem) { store.switchSpace(to: sender.tag) }
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
        let webView = WKWebView(frame: .zero, configuration: store.space.makeConfiguration())
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

    /// `--snapshot <path>` writes a PNG of the window and quits. Used to check layout without a human.
    private func snapshot(to path: String) {
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
        view.cacheDisplay(in: view.bounds, to: rep)

        func write(_ web: NSImage?, _ frame: NSRect) {
            let image = NSImage(size: view.bounds.size)
            image.lockFocus()
            if let web, store.commandBar == nil, !store.peeking {
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
