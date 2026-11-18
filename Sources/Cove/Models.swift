import AppKit
import Combine
import SwiftUI
import WebKit

// MARK: - Tab

@MainActor
final class BrowserTab: NSObject, ObservableObject, Identifiable {
    let id: UUID
    weak var space: Space?
    weak var store: BrowserStore?

    @Published var title: String
    @Published var url: URL
    @Published var favicon: NSImage?
    @Published var isLoading = false
    @Published var canGoBack = false
    @Published var canGoForward = false

    /// Created the first time the tab is selected, so pinned tabs cost nothing until opened.
    private(set) var webView: WKWebView?
    private var bag = Set<AnyCancellable>()
    private var iconTask: Task<Void, Never>?

    /// When the tab was last on screen. The idle sweep unloads tabs that have sat past the limit.
    var lastActive = Date()
    /// Back-forward history and scroll position, kept while the tab is unloaded.
    private var savedState: Any?

    /// History and scroll position in a form that can be written to disk.
    var persistableState: Data? {
        (webView?.interactionState ?? savedState) as? Data
    }

    init(title: String, url: URL, id: UUID = UUID(), state: Data? = nil) {
        self.id = id
        self.title = title
        self.url = url
        self.savedState = state
        super.init()
        fetchIcon(candidates: [Self.rootIcon(for: url)].compactMap { $0 })
    }

    var host: String {
        let h = url.host ?? url.absoluteString
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    @discardableResult
    func ensureWebView(configuration: WKWebViewConfiguration? = nil) -> WKWebView {
        if let webView { return webView }
        let config = configuration ?? space?.makeConfiguration() ?? WKWebViewConfiguration()
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.allowsBackForwardNavigationGestures = true
        wv.allowsMagnification = true
        wv.isInspectable = true
        webView = wv

        wv.publisher(for: \.title).sink { [weak self] t in
            if let t, !t.isEmpty { self?.title = t }
        }.store(in: &bag)
        wv.publisher(for: \.url).sink { [weak self] u in
            if let u { self?.url = u }
        }.store(in: &bag)
        wv.publisher(for: \.isLoading).sink { [weak self] in self?.isLoading = $0 }.store(in: &bag)
        wv.publisher(for: \.canGoBack).sink { [weak self] in self?.canGoBack = $0 }.store(in: &bag)
        wv.publisher(for: \.canGoForward).sink { [weak self] in self?.canGoForward = $0 }.store(in: &bag)

        // A popup arrives with its own configuration and loads itself.
        if configuration == nil {
            if let savedState {
                wv.interactionState = savedState
                self.savedState = nil
            } else {
                wv.load(URLRequest(url: url))
            }
        }
        return wv
    }

    /// True while unloading would interrupt something: a page still loading, a call, or playing audio.
    var isBusy: Bool {
        guard let webView else { return false }
        if webView.isLoading { return true }
        if webView.cameraCaptureState != .none || webView.microphoneCaptureState != .none { return true }
        // WebKit has no public "is this page making sound" property.
        let playing = NSSelectorFromString("_isPlayingAudio")
        if webView.responds(to: playing), (webView.value(forKey: "_isPlayingAudio") as? Bool) == true { return true }
        return false
    }

    /// Frees the page's memory. The tab stays in the sidebar and reloads where it was when selected again.
    func unload() {
        guard let webView else { return }
        savedState = webView.interactionState
        bag.removeAll()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
        webView.removeFromSuperview()
        self.webView = nil
        isLoading = false
        canGoBack = false
        canGoForward = false
    }

    func load(_ url: URL) {
        self.url = url
        ensureWebView().load(URLRequest(url: url))
    }

    // MARK: Favicon

    private static func rootIcon(for url: URL) -> URL? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        return URL(string: "\(scheme)://\(host)/favicon.ico")
    }

    private func refreshFavicon() {
        guard let webView else { return }
        let js = """
        [...document.querySelectorAll('link[rel~="icon"], link[rel="apple-touch-icon"]')].map(e => e.href)
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self else { return }
            var candidates = (result as? [String] ?? []).compactMap { URL(string: $0) }
            if let root = Self.rootIcon(for: self.url) { candidates.append(root) }
            self.fetchIcon(candidates: candidates)
        }
    }

    private func fetchIcon(candidates: [URL]) {
        iconTask?.cancel()
        iconTask = Task { [weak self] in
            for candidate in candidates {
                guard let (data, _) = try? await URLSession.shared.data(from: candidate),
                      let image = NSImage(data: data), image.isValid, image.size.width > 0
                else { continue }
                if Task.isCancelled { return }
                self?.favicon = image
                return
            }
        }
    }
}

extension BrowserTab: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshFavicon()
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Cmd-click opens the link in a background tab.
        if navigationAction.navigationType == .linkActivated,
           navigationAction.modifierFlags.contains(.command),
           let target = navigationAction.request.url {
            store?.newTab(url: target, select: false)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // target=_blank and window.open land in a new tab that keeps its opener.
        guard let store, let space else { return nil }
        let tab = BrowserTab(title: "New Tab", url: navigationAction.request.url ?? url)
        tab.space = space
        tab.store = store
        let wv = tab.ensureWebView(configuration: configuration)
        space.today.insert(tab, at: 0)
        store.select(tab)
        return wv
    }

    func webViewDidClose(_ webView: WKWebView) {
        store?.close(self)
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.begin { completionHandler($0 == .OK ? panel.urls : nil) }
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.prompt)
    }
}

// MARK: - Folder

@MainActor
final class TabFolder: ObservableObject, Identifiable {
    let id = UUID()
    @Published var name: String
    @Published var expanded: Bool
    @Published var tabs: [BrowserTab]

    init(name: String, expanded: Bool = false, tabs: [BrowserTab]) {
        self.name = name
        self.expanded = expanded
        self.tabs = tabs
    }
}

// MARK: - Space

/// A space owns its tabs and one profile. The profile is a WebKit data store,
/// so cookies, logins and site storage never cross between spaces.
@MainActor
final class Space: ObservableObject, Identifiable {
    let id = UUID()
    let name: String
    let symbol: String
    let hue: Double
    let profileID: UUID

    @Published var favorites: [BrowserTab]
    @Published var pinned: [BrowserTab]
    @Published var folders: [TabFolder]
    @Published var today: [BrowserTab]
    @Published var selected: BrowserTab?

    private lazy var dataStore = WKWebsiteDataStore(forIdentifier: profileID)

    init(name: String, symbol: String, hue: Double, profileID: UUID,
         favorites: [BrowserTab] = [], pinned: [BrowserTab] = [],
         folders: [TabFolder] = [], today: [BrowserTab] = []) {
        self.name = name
        self.symbol = symbol
        self.hue = hue
        self.profileID = profileID
        self.favorites = favorites
        self.pinned = pinned
        self.folders = folders
        self.today = today
    }

    var allTabs: [BrowserTab] {
        favorites + pinned + folders.flatMap(\.tabs) + today
    }

    /// The installed Safari's version, so the user agent matches the engine underneath.
    /// A made-up version is one of the mismatches that bot checks look for.
    private static let safariVersion: String = {
        let plist = URL(fileURLWithPath: "/Applications/Safari.app/Contents/Info.plist")
        let info = NSDictionary(contentsOf: plist)
        return info?["CFBundleShortVersionString"] as? String ?? "26.0"
    }()

    func makeConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStore
        // Sites sniff for Safari. Without this suffix some of them serve a degraded page.
        config.applicationNameForUserAgent = "Version/\(Self.safariVersion) Safari/605.1.15"
        config.preferences.isElementFullscreenEnabled = true
        // Turns on Inspect Element in the right-click menu and the Web Inspector window.
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsAirPlayForMediaPlayback = true
        return config
    }
}

// MARK: - Store

enum CommandBarMode { case newTab, editURL }

enum Suggestion: Identifiable {
    case go(URL, String, isSearch: Bool)
    case tab(BrowserTab)

    var id: String {
        switch self {
        case .go(let url, _, _): return "go:" + url.absoluteString
        case .tab(let tab): return "tab:" + tab.id.uuidString
        }
    }
}

@MainActor
final class BrowserStore: ObservableObject {
    @Published var spaces: [Space]
    @Published var spaceIndex = 0
    /// Where the sidebar strip sits, in spaces. 0.5 is halfway between the first and second.
    @Published var pagePosition: Double = 0
    @Published var peeking = false
    @Published var sidebarVisible = true
    @Published var commandBar: CommandBarMode?
    @Published var query = ""
    @Published var highlight = 0

    weak var window: NSWindow?
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var idleTimer: Timer?
    private var saveTask: Task<Void, Never>?
    /// False for diagnostic runs, so a test launch never reads or overwrites the real session.
    private let persist: Bool

    /// How long a background tab may sit before its page is unloaded.
    /// COVE_IDLE_SECONDS overrides it, which is how the unload path gets tested in seconds.
    static let idleLimit: TimeInterval = {
        if let text = ProcessInfo.processInfo.environment["COVE_IDLE_SECONDS"], let seconds = TimeInterval(text) {
            return seconds
        }
        return 10 * 60
    }()
    private var swipe = SwipeState()

    private struct SwipeState {
        enum Axis { case undecided, horizontal, vertical }
        var axis = Axis.undecided
        var inSidebar = false
        var travelX: CGFloat = 0
        var travelY: CGFloat = 0
        var lastDeltaX: CGFloat = 0
        var swallowMomentum = false
    }

    var space: Space { spaces[spaceIndex] }
    var selectedTab: BrowserTab? { space.selected }

    init(persist: Bool = true) {
        self.persist = persist
        let saved = persist ? Self.readSession() : nil
        spaces = saved.map(Self.spaces(from:)) ?? Self.seed()
        for space in spaces {
            for tab in space.allTabs {
                tab.space = space
                tab.store = self
            }
        }
        if let saved {
            spaceIndex = min(max(saved.spaceIndex, 0), spaces.count - 1)
            pagePosition = Double(spaceIndex)
            sidebarVisible = saved.sidebarVisible
            for (space, record) in zip(spaces, saved.spaces) {
                space.selected = space.allTabs.first { $0.id == record.selected }
            }
            // Only the tab on screen loads at launch. The rest load when clicked.
            selectedTab?.ensureWebView()
        } else if let first = spaces[0].today.first {
            select(first)
        }

        // Arrow keys and Escape drive the command bar while the text field has focus.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.commandBar != nil else { return event }
            switch event.keyCode {
            case 125: self.highlight = min(self.highlight + 1, max(self.suggestions.count - 1, 0)); return nil
            case 126: self.highlight = max(self.highlight - 1, 0); return nil
            case 53: self.closeCommandBar(); return nil
            default: return event
            }
        }

        idleTimer = Timer.scheduledTimer(withTimeInterval: min(60, Self.idleLimit / 2), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.unloadIdleTabs()
                // Catches what no action announces: new titles, new URLs, folders opened.
                self?.scheduleSave()
            }
        }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            return self.handleScroll(event) ? nil : event
        }
    }

    // MARK: Swiping between spaces

    /// Returns true when the event belongs to a space swipe and must not reach the views below.
    private func handleScroll(_ event: NSEvent) -> Bool {
        guard event.window === window, event.hasPreciseScrollingDeltas else { return false }

        // The glide after the fingers lift would otherwise scroll whatever is under the pointer.
        if event.phase.isEmpty {
            if swipe.swallowMomentum {
                if event.momentumPhase == .ended || event.momentumPhase == .cancelled { swipe.swallowMomentum = false }
                return !event.momentumPhase.isEmpty
            }
            return false
        }

        if event.phase.contains(.began) {
            swipe = SwipeState()
            let x = event.locationInWindow.x
            swipe.inSidebar = commandBar == nil && (sidebarVisible || peeking) && x <= Metrics.sidebarWidth + 6
        }
        guard swipe.inSidebar else { return false }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            guard swipe.axis == .horizontal else { return false }
            settleSwipe()
            swipe.swallowMomentum = true
            return true
        }

        if swipe.axis == .undecided {
            swipe.travelX += event.scrollingDeltaX
            swipe.travelY += event.scrollingDeltaY
            if abs(swipe.travelX) + abs(swipe.travelY) > 3 {
                swipe.axis = abs(swipe.travelX) > abs(swipe.travelY) ? .horizontal : .vertical
            }
        }
        guard swipe.axis == .horizontal else { return false }

        // Past the first or last space the strip resists, like a scroll view at its edge.
        let last = Double(spaces.count - 1)
        let outside = pagePosition < 0 || pagePosition > last
        let step = Double(event.scrollingDeltaX) / Double(Metrics.sidebarWidth)
        pagePosition -= step * (outside ? 0.25 : 1)
        swipe.lastDeltaX = event.scrollingDeltaX
        return true
    }

    private func settleSwipe() {
        let moved = pagePosition - Double(spaceIndex)
        var target = spaceIndex
        // A quick flick counts even when it covered little distance.
        if abs(swipe.lastDeltaX) > 6 {
            target += swipe.lastDeltaX < 0 ? 1 : -1
        } else if abs(moved) > 0.3 {
            target += moved > 0 ? 1 : -1
        }
        switchSpace(to: min(max(target, 0), spaces.count - 1))
    }

    // MARK: Idle tabs

    /// Unloads every background tab that has been off screen longer than the limit.
    /// The tab on screen is never touched, and neither is one that is busy.
    func unloadIdleTabs() {
        let now = Date()
        for space in spaces {
            for tab in space.allTabs where tab.webView != nil && tab !== selectedTab {
                if now.timeIntervalSince(tab.lastActive) > Self.idleLimit, !tab.isBusy {
                    tab.unload()
                }
            }
        }
    }

    var loadedTabCount: Int {
        spaces.flatMap(\.allTabs).filter { $0.webView != nil }.count
    }

    // MARK: Tabs

    func select(_ tab: BrowserTab) {
        guard let owner = tab.space else { return }
        // The idle clock for the tab being left starts now.
        selectedTab?.lastActive = Date()
        tab.lastActive = Date()
        tab.ensureWebView()
        owner.selected = tab
        if let index = spaces.firstIndex(where: { $0 === owner }), index != spaceIndex {
            switchSpace(to: index)
        }
        focusWeb()
        scheduleSave()
    }

    @discardableResult
    func newTab(url: URL, select shouldSelect: Bool = true) -> BrowserTab {
        let tab = BrowserTab(title: url.host ?? "New Tab", url: url)
        tab.space = space
        tab.store = self
        space.today.insert(tab, at: 0)
        if shouldSelect { select(tab) } else { tab.ensureWebView() }
        scheduleSave()
        return tab
    }

    func close(_ tab: BrowserTab) {
        guard let owner = tab.space else { return }
        let order = owner.allTabs
        let position = order.firstIndex(where: { $0 === tab })

        owner.favorites.removeAll { $0 === tab }
        owner.pinned.removeAll { $0 === tab }
        owner.today.removeAll { $0 === tab }
        for folder in owner.folders { folder.tabs.removeAll { $0 === tab } }

        if owner.selected === tab {
            let remaining = owner.allTabs
            if let position, !remaining.isEmpty {
                let next = remaining[min(position, remaining.count - 1)]
                next.lastActive = Date()
                next.ensureWebView()
                owner.selected = next
            } else {
                owner.selected = nil
            }
        }
        scheduleSave()
    }

    func closeSelected() {
        if let tab = selectedTab { close(tab) }
    }

    func togglePin(_ tab: BrowserTab) {
        guard let owner = tab.space else { return }
        if let index = owner.today.firstIndex(where: { $0 === tab }) {
            owner.today.remove(at: index)
            owner.pinned.append(tab)
        } else if let index = owner.pinned.firstIndex(where: { $0 === tab }) {
            owner.pinned.remove(at: index)
            owner.today.insert(tab, at: 0)
        }
        scheduleSave()
    }

    func isPinned(_ tab: BrowserTab) -> Bool {
        tab.space?.today.contains(where: { $0 === tab }) == false
    }

    func cycle(_ step: Int) {
        let order = space.allTabs
        guard !order.isEmpty else { return }
        let current = order.firstIndex(where: { $0 === selectedTab }) ?? 0
        select(order[(current + step + order.count) % order.count])
    }

    func clearToday() {
        for tab in space.today where tab !== selectedTab { close(tab) }
    }

    func copyURL() {
        guard let url = selectedTab?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    // MARK: Spaces

    func switchSpace(to index: Int) {
        guard spaces.indices.contains(index) else { return }
        selectedTab?.lastActive = Date()
        withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
            pagePosition = Double(index)
            spaceIndex = index
        }
        // A space opened for the first time shows its newest tab, not an empty card.
        if space.selected == nil, let first = space.today.first ?? space.pinned.first {
            space.selected = first
        }
        // The space's tab may have been unloaded while the space was off screen.
        space.selected?.lastActive = Date()
        space.selected?.ensureWebView()
        focusWeb()
        scheduleSave()
    }

    func stepSpace(_ step: Int) {
        switchSpace(to: min(max(spaceIndex + step, 0), spaces.count - 1))
    }

    // MARK: Command bar

    func openCommandBar(_ mode: CommandBarMode) {
        query = mode == .editURL ? (selectedTab?.url.absoluteString ?? "") : ""
        highlight = 0
        commandBar = mode
    }

    func closeCommandBar() {
        commandBar = nil
        focusWeb()
    }

    var suggestions: [Suggestion] {
        let text = query.trimmingCharacters(in: .whitespaces)
        let tabs = space.allTabs
        if text.isEmpty {
            return tabs.filter { $0 !== selectedTab }.prefix(6).map { .tab($0) }
        }
        let needle = text.lowercased()
        let matches = tabs.filter {
            $0.title.lowercased().contains(needle) || $0.host.lowercased().contains(needle)
        }
        let (url, isSearch) = Self.resolve(text)
        let label = isSearch ? text : (url.host ?? text)
        return [.go(url, label, isSearch: isSearch)] + matches.prefix(5).map { .tab($0) }
    }

    func submit() {
        let list = suggestions
        guard list.indices.contains(highlight) else { closeCommandBar(); return }
        run(list[highlight])
    }

    func run(_ suggestion: Suggestion) {
        let mode = commandBar
        commandBar = nil
        switch suggestion {
        case .tab(let tab):
            select(tab)
        case .go(let url, _, _):
            if mode == .editURL, let tab = selectedTab {
                tab.load(url)
                focusWeb()
            } else {
                newTab(url: url)
            }
        }
    }

    /// Turns typed text into a URL, or a search when it does not look like an address.
    static func resolve(_ text: String) -> (URL, isSearch: Bool) {
        if text.contains("://"), let url = URL(string: text) { return (url, false) }
        let looksLikeHost = !text.contains(" ") && (text.contains(".") || text.hasPrefix("localhost"))
        if looksLikeHost, let url = URL(string: (text.hasPrefix("localhost") ? "http://" : "https://") + text) {
            return (url, false)
        }
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: text)]
        return (components.url!, true)
    }

    private func focusWeb() {
        guard let webView = selectedTab?.webView else { return }
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(webView)
        }
    }

    // MARK: Seed data

    private static func tab(_ title: String, _ address: String) -> BrowserTab {
        BrowserTab(title: title, url: URL(string: address)!)
    }

    private static func seed() -> [Space] {
        // Fixed profile ids, so logins survive a relaunch.
        let personal = Space(
            name: "Personal", symbol: "leaf.fill", hue: 0.72,
            profileID: UUID(uuidString: "6F1E7C1A-0B5D-4C3E-9A41-1D2B3C4D5E01")!,
            favorites: [
                tab("Gmail", "https://mail.google.com"),
                tab("YouTube", "https://www.youtube.com"),
                tab("Netflix", "https://www.netflix.com"),
                tab("Spotify", "https://open.spotify.com"),
                tab("X", "https://x.com"),
                tab("GitHub", "https://github.com"),
            ],
            pinned: [
                tab("Hacker News", "https://news.ycombinator.com"),
                tab("Figma", "https://www.figma.com"),
            ],
            folders: [
                TabFolder(name: "Reading", tabs: [
                    tab("WebKit Blog", "https://webkit.org/blog/"),
                    tab("MDN Web Docs", "https://developer.mozilla.org"),
                ])
            ],
            today: [
                tab("Wikipedia", "https://www.wikipedia.org"),
                tab("Apple", "https://www.apple.com"),
            ]
        )
        let work = Space(
            name: "Work", symbol: "briefcase.fill", hue: 0.56,
            profileID: UUID(uuidString: "6F1E7C1A-0B5D-4C3E-9A41-1D2B3C4D5E02")!,
            favorites: [
                tab("Gmail", "https://mail.google.com"),
                tab("Linear", "https://linear.app"),
                tab("Notion", "https://www.notion.so"),
            ],
            pinned: [
                tab("GitHub", "https://github.com"),
            ],
            today: [
                tab("Can I use", "https://caniuse.com"),
            ]
        )
        return [personal, work]
    }
}

// MARK: - Session file

private struct SavedTab: Codable {
    var id: UUID
    var title: String
    var url: URL
    var state: Data?
}

private struct SavedFolder: Codable {
    var name: String
    var expanded: Bool
    var tabs: [SavedTab]
}

private struct SavedSpace: Codable {
    var name: String
    var symbol: String
    var hue: Double
    var profileID: UUID
    var favorites: [SavedTab]
    var pinned: [SavedTab]
    var folders: [SavedFolder]
    var today: [SavedTab]
    var selected: UUID?
}

private struct SavedSession: Codable {
    var version = 1
    var spaceIndex: Int
    var sidebarVisible: Bool
    var spaces: [SavedSpace]
}

extension BrowserStore {
    /// ~/Library/Application Support/Cove/session.json, unless COVE_SESSION_FILE points elsewhere.
    private static var sessionURL: URL {
        if let path = ProcessInfo.processInfo.environment["COVE_SESSION_FILE"] {
            return URL(fileURLWithPath: path)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Cove/session.json")
    }

    /// Saves a moment after the last change, so a burst of actions costs one write.
    func scheduleSave() {
        guard persist else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        guard persist else { return }
        func record(_ tab: BrowserTab) -> SavedTab {
            SavedTab(id: tab.id, title: tab.title, url: tab.url, state: tab.persistableState)
        }
        let session = SavedSession(
            spaceIndex: spaceIndex,
            sidebarVisible: sidebarVisible,
            spaces: spaces.map { space in
                SavedSpace(
                    name: space.name, symbol: space.symbol, hue: space.hue, profileID: space.profileID,
                    favorites: space.favorites.map(record),
                    pinned: space.pinned.map(record),
                    folders: space.folders.map {
                        SavedFolder(name: $0.name, expanded: $0.expanded, tabs: $0.tabs.map(record))
                    },
                    today: space.today.map(record),
                    selected: space.selected?.id
                )
            }
        )
        let url = Self.sessionURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(session).write(to: url, options: .atomic)
        } catch {
            NSLog("Cove could not save the session: \(error.localizedDescription)")
        }
    }

    /// Returns nil on first launch, or when the file is unreadable. The caller then starts from the sample set.
    fileprivate static func readSession() -> SavedSession? {
        guard let data = try? Data(contentsOf: sessionURL),
              let session = try? JSONDecoder().decode(SavedSession.self, from: data),
              !session.spaces.isEmpty
        else { return nil }
        return session
    }

    fileprivate static func spaces(from session: SavedSession) -> [Space] {
        func tab(_ record: SavedTab) -> BrowserTab {
            BrowserTab(title: record.title, url: record.url, id: record.id, state: record.state)
        }
        return session.spaces.map { record in
            Space(
                name: record.name, symbol: record.symbol, hue: record.hue, profileID: record.profileID,
                favorites: record.favorites.map(tab),
                pinned: record.pinned.map(tab),
                folders: record.folders.map {
                    TabFolder(name: $0.name, expanded: $0.expanded, tabs: $0.tabs.map(tab))
                },
                today: record.today.map(tab)
            )
        }
    }
}
