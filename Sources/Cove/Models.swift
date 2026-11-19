import AppKit
import Combine
import SwiftUI
import WebKit

// MARK: - Tab

@MainActor
final class BrowserTab: NSObject, ObservableObject, Identifiable {
    let id: UUID
    /// Whose cookies and logins this tab uses. The store sets it whenever the tab moves.
    weak var profile: Profile?
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
        if let cached = FaviconCache.image(for: host) {
            favicon = cached
        } else {
            fetchIcon(candidates: [Self.rootIcon(for: url)].compactMap { $0 })
        }
    }

    var host: String {
        let h = url.host ?? url.absoluteString
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    @discardableResult
    func ensureWebView(configuration: WKWebViewConfiguration? = nil) -> WKWebView {
        if let webView { return webView }
        let config = configuration ?? profile?.makeConfiguration() ?? WKWebViewConfiguration()
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
        let host = host
        iconTask = Task { [weak self] in
            for candidate in candidates {
                guard let (data, _) = try? await URLSession.shared.data(from: candidate),
                      let image = NSImage(data: data), image.isValid, image.size.width > 0
                else { continue }
                if Task.isCancelled { return }
                self?.favicon = image
                FaviconCache.store(data, image: image, host: host)
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
        guard let store else { return nil }
        let tab = BrowserTab(title: "New Tab", url: navigationAction.request.url ?? url)
        tab.profile = profile
        tab.store = store
        let wv = tab.ensureWebView(configuration: configuration)
        (store.space(owning: self) ?? store.space).today.insert(tab, at: 0)
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

// MARK: - Favicon cache

/// One icon per host, kept on disk so a launch with hundreds of tabs does not refetch them all.
@MainActor
enum FaviconCache {
    private static var memory: [String: NSImage] = [:]
    private static let folder: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let folder = caches.appendingPathComponent("Cove/favicons")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    private static func file(for host: String) -> URL {
        let safe = host.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" }
        return folder.appendingPathComponent(String(safe))
    }

    static func image(for host: String) -> NSImage? {
        if let hit = memory[host] { return hit }
        guard let data = try? Data(contentsOf: file(for: host)), let image = NSImage(data: data) else { return nil }
        memory[host] = image
        return image
    }

    static func store(_ data: Data, image: NSImage, host: String) {
        memory[host] = image
        try? data.write(to: file(for: host), options: .atomic)
    }
}

// MARK: - Folders and the pinned tree

/// One entry in a space's pinned area. Folders nest.
@MainActor
enum Node: Identifiable {
    case tab(BrowserTab)
    case folder(TabFolder)

    nonisolated var id: UUID {
        switch self {
        case .tab(let tab): return tab.id
        case .folder(let folder): return folder.id
        }
    }

    /// Every tab at or under this entry, in sidebar order.
    var tabs: [BrowserTab] {
        switch self {
        case .tab(let tab): return [tab]
        case .folder(let folder): return folder.tabs
        }
    }
}

@MainActor
final class TabFolder: ObservableObject, Identifiable {
    let id: UUID
    @Published var name: String
    @Published var expanded: Bool
    @Published var children: [Node]

    init(name: String, expanded: Bool = false, children: [Node] = [], id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.expanded = expanded
        self.children = children
    }

    var tabs: [BrowserTab] { children.flatMap(\.tabs) }

    /// This folder and every folder inside it.
    var folders: [TabFolder] {
        [self] + children.flatMap { node -> [TabFolder] in
            if case .folder(let folder) = node { return folder.folders }
            return []
        }
    }
}

// MARK: - Profile

/// A profile is a WebKit data store: one set of cookies, logins and site storage.
/// Several spaces can share a profile. Favorites belong to the profile, so they show in each of its spaces.
@MainActor
final class Profile: ObservableObject, Identifiable {
    let id: UUID
    @Published var name: String
    @Published var favorites: [BrowserTab]

    private lazy var dataStore = WKWebsiteDataStore(forIdentifier: id)

    init(name: String, id: UUID = UUID(), favorites: [BrowserTab] = []) {
        self.id = id
        self.name = name
        self.favorites = favorites
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

// MARK: - Space

/// A space is a named, themed set of tabs that browses with one profile.
@MainActor
final class Space: ObservableObject, Identifiable {
    let id: UUID
    @Published var name: String
    /// An emoji, or the name of an SF Symbol.
    @Published var icon: String
    @Published var theme: SpaceTheme
    let profile: Profile

    @Published var pinned: [Node]
    @Published var today: [BrowserTab]
    @Published var selected: BrowserTab?
    /// When true the pinned tabs and folders are folded away, leaving the favorites and today's tabs.
    @Published var pinnedCollapsed: Bool

    init(name: String, icon: String, theme: SpaceTheme, profile: Profile, id: UUID = UUID(),
         pinned: [Node] = [], today: [BrowserTab] = [], pinnedCollapsed: Bool = false) {
        self.id = id
        self.name = name
        self.icon = icon
        self.theme = theme
        self.profile = profile
        self.pinned = pinned
        self.today = today
        self.pinnedCollapsed = pinnedCollapsed
    }

    /// Pinned and today's tabs. Favorites are left out because the profile owns them.
    var ownTabs: [BrowserTab] { pinned.flatMap(\.tabs) + today }
    var allTabs: [BrowserTab] { profile.favorites + ownTabs }

    var folders: [TabFolder] {
        pinned.flatMap { node -> [TabFolder] in
            if case .folder(let folder) = node { return folder.folders }
            return []
        }
    }
}
