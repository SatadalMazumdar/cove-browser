import AppKit
import Combine
import SwiftUI
import WebKit

enum CommandBarMode { case newTab, editURL }

enum Suggestion: Identifiable {
    case go(URL, String, isSearch: Bool)
    case tab(BrowserTab)
    /// The "Active Tabs" command. Enter on it drills into the sub-view. Carries the loaded-tab count.
    case activeTabs(Int)

    var id: String {
        switch self {
        case .go(let url, _, _): return "go:" + url.absoluteString
        case .tab(let tab): return "tab:" + tab.id.uuidString
        case .activeTabs: return "cmd:activeTabs"
        }
    }
}

/// What is being dragged in the sidebar.
enum DragItem: Equatable {
    case node(UUID)
    case space(UUID)
}

/// Where a drag can land.
enum DropTarget: Equatable {
    /// In front of this tab or folder, wherever it sits.
    case before(UUID)
    case intoFolder(UUID)
    case pinnedEnd(space: UUID)
    case todayStart(space: UUID)
    case todayEnd(space: UUID)
    case favoritesEnd(profile: UUID)
    /// A space's icon. A tab lands in that space. A dragged space takes this one's position.
    case space(UUID)
}

/// The centred panels that sit above the page.
enum Panel {
    case space(SpaceDraft)
    case arcImport(ArcImportDraft)
    case settings
}

@MainActor
final class BrowserStore: ObservableObject {
    @Published var profiles: [Profile]
    @Published var spaces: [Space]
    @Published var spaceIndex = 0
    /// Where the sidebar strip sits, in spaces. 0.5 is halfway between the first and second.
    @Published var pagePosition: Double = 0
    @Published var peeking = false
    @Published var sidebarVisible = true
    /// True while the window is in system full screen. The page drops its gutter then.
    @Published var fullScreen = false
    /// Ad and tracker blocking, on by default.
    @Published var blockingEnabled = true
    @Published var commandBar: CommandBarMode?
    @Published var query = ""
    @Published var highlight = 0
    /// Inside the command bar's active-tabs sub-view.
    @Published var showingActiveTabs = false
    @Published var panel: Panel?
    /// The spot a drag is hovering over, so the sidebar can draw the insertion mark.
    @Published var dropTarget: DropTarget?
    /// Goes up whenever spaces are added, removed, renamed or reordered. The menu bar rebuilds on it.
    @Published var revision = 0

    /// Files downloaded from any page, shared across tabs and profiles.
    let downloads = DownloadManager()
    /// Visited pages, for command bar suggestions.
    let history: History
    var dragging: DragItem?
    weak var window: NSWindow?
    /// True when no session file existed, so this launch shows the sample tabs.
    let startedFromSeed: Bool
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var mouseMonitor: Any?
    private var idleTimer: Timer?
    private var saveTask: Task<Void, Never>?
    /// False for diagnostic runs, so a test launch never reads or overwrites the real session.
    let persist: Bool

    /// How long a background tab may sit before its page is unloaded, 0 to never unload.
    /// Settings changes it. COVE_IDLE_SECONDS sets the starting value, which is how the path gets tested.
    @Published var idleSeconds: TimeInterval = BrowserStore.defaultIdle

    static let defaultIdle: TimeInterval = {
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
        // Diagnostic runs do not touch the real history unless a test file is pointed at it.
        history = History(open: persist || ProcessInfo.processInfo.environment["COVE_HISTORY_FILE"] != nil)
        let saved = persist ? SessionFile.load() : nil
        startedFromSeed = saved == nil
        if let saved {
            profiles = saved.profiles
            spaces = saved.spaces
        } else {
            (profiles, spaces) = Self.seed()
        }
        wire()
        ContentBlocker.shared.enabled = blockingEnabled
        ContentBlocker.shared.onReady = { [weak self] in self?.applyBlocking() }
        ContentBlocker.shared.prepare()
        if let saved {
            spaceIndex = min(max(saved.spaceIndex, 0), spaces.count - 1)
            pagePosition = Double(spaceIndex)
            sidebarVisible = saved.sidebarVisible
            if let seconds = saved.idleSeconds { idleSeconds = seconds }
            if let blocking = saved.blockingEnabled { blockingEnabled = blocking }
            // Only the tab on screen loads at launch. The rest load when clicked.
            selectedTab?.ensureWebView()
            // Writes the file back in the current format when it was read from an older one.
            scheduleSave()
        } else if let first = spaces[0].today.first {
            select(first)
        }

        // Arrow keys and Escape drive the command bar while the text field has focus.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.panel != nil {
                if event.keyCode == 53 { self.closePanel(); return nil }
                return event
            }
            guard self.commandBar != nil else { return event }
            // The active-tabs sub-view is driven entirely from the keyboard: arrows move, Return
            // switches, Cmd+Return sleeps, Cmd+Delete closes, Escape steps back to search.
            if self.showingActiveTabs {
                let count = self.activeMatches.count
                switch event.keyCode {
                case 53: self.showingActiveTabs = false; self.query = ""; self.highlight = 0; return nil
                case 125: self.highlight = min(self.highlight + 1, max(count - 1, 0)); return nil
                case 126: self.highlight = max(self.highlight - 1, 0); return nil
                case 51 where event.modifierFlags.contains(.command):
                    self.closeActiveTab(at: self.highlight); return nil
                case 36 where event.modifierFlags.contains(.command):
                    self.sleepActiveTab(at: self.highlight); return nil
                default: return event
                }
            }
            switch event.keyCode {
            case 125: self.highlight = min(self.highlight + 1, max(self.suggestions.count - 1, 0)); return nil
            case 126: self.highlight = max(self.highlight - 1, 0); return nil
            case 53: self.closeCommandBar(); return nil
            default: return event
            }
        }

        idleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
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

        // The floating sidebar closes when the pointer leaves it. Its SwiftUI hover-exit is
        // unreliable over a web view, so the pointer position is tracked directly as a backstop.
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] event in
            self?.trackPeek(event)
            return event
        }
    }

    /// Closes the floating sidebar once the pointer moves past its right edge, or on a click outside it.
    private func trackPeek(_ event: NSEvent) {
        guard peeking, event.window === window else { return }
        if event.locationInWindow.x > Metrics.sidebarWidth + 14 {
            peeking = false
        }
    }

    // MARK: Structure

    /// Every tab in the app, favorites included.
    var everyTab: [BrowserTab] {
        profiles.flatMap(\.favorites) + spaces.flatMap(\.ownTabs)
    }

    /// Points each tab at its profile. A tab that changed profile drops its page,
    /// because the page was loaded with the old profile's cookies.
    private func wire() {
        func attach(_ tab: BrowserTab, _ profile: Profile) {
            if tab.profile !== profile {
                if tab.profile != nil { tab.unload() }
                tab.profile = profile
            }
            tab.store = self
        }
        for profile in profiles {
            for tab in profile.favorites { attach(tab, profile) }
        }
        for space in spaces {
            for tab in space.ownTabs { attach(tab, space.profile) }
        }
    }

    /// Run after tabs, folders or spaces move. Repairs links and selection, then saves.
    func structureChanged() {
        wire()
        for space in spaces {
            if let selected = space.selected, !space.allTabs.contains(where: { $0 === selected }) {
                space.selected = space.today.first ?? space.ownTabs.first
            }
        }
        selectedTab?.ensureWebView()
        revision += 1
        scheduleSave()
    }

    func space(owning tab: BrowserTab) -> Space? {
        spaces.first { $0.ownTabs.contains { $0 === tab } }
    }

    func isFavorite(_ tab: BrowserTab) -> Bool {
        profiles.contains { $0.favorites.contains { $0 === tab } }
    }

    private func folder(_ id: UUID) -> TabFolder? {
        for space in spaces {
            if let hit = space.folders.first(where: { $0.id == id }) { return hit }
        }
        return nil
    }

    private func node(_ id: UUID) -> Node? {
        if let tab = everyTab.first(where: { $0.id == id }) { return .tab(tab) }
        return folder(id).map { .folder($0) }
    }

    @discardableResult
    private func remove(_ id: UUID, from nodes: inout [Node]) -> Node? {
        if let index = nodes.firstIndex(where: { $0.id == id }) { return nodes.remove(at: index) }
        for case .folder(let folder) in nodes {
            if let found = remove(id, from: &folder.children) { return found }
        }
        return nil
    }

    private func insert(_ node: Node, before id: UUID, in nodes: inout [Node]) -> Bool {
        if let index = nodes.firstIndex(where: { $0.id == id }) {
            nodes.insert(node, at: index)
            return true
        }
        for case .folder(let folder) in nodes {
            if insert(node, before: id, in: &folder.children) { return true }
        }
        return false
    }

    /// Takes a tab or folder out of wherever it sits.
    private func detach(_ id: UUID) -> Node? {
        for profile in profiles {
            if let index = profile.favorites.firstIndex(where: { $0.id == id }) {
                return .tab(profile.favorites.remove(at: index))
            }
        }
        for space in spaces {
            if let found = remove(id, from: &space.pinned) { return found }
            if let index = space.today.firstIndex(where: { $0.id == id }) {
                return .tab(space.today.remove(at: index))
            }
        }
        return nil
    }

    // MARK: Drag and drop

    func canDrop(on target: DropTarget) -> Bool {
        guard let dragging else { return false }
        switch dragging {
        case .space(let id):
            if case .space(let other) = target { return other != id }
            return false
        case .node(let id):
            guard let node = node(id) else { return false }
            if case .before(let other) = target, other == id { return false }
            guard case .folder(let folder) = node else { return true }
            // Folders live in the pinned area only, and never inside themselves.
            switch target {
            case .pinnedEnd: return true
            case .intoFolder(let other): return !folder.folders.contains { $0.id == other }
            case .before(let other):
                if folder.folders.contains(where: { $0.id == other }) { return false }
                if folder.tabs.contains(where: { $0.id == other }) { return false }
                return spaces.contains { $0.pinned.flatMap(\.tabs).contains { $0.id == other } }
                    || self.folder(other) != nil
            default: return false
            }
        }
    }

    /// Moves the dragged item to the target. Also used by the context menus.
    @discardableResult
    func drop(_ item: DragItem, on target: DropTarget) -> Bool {
        dragging = item
        defer {
            dragging = nil
            dropTarget = nil
        }
        guard canDrop(on: target) else { return false }

        switch item {
        case .space(let id):
            guard case .space(let other) = target,
                  let from = spaces.firstIndex(where: { $0.id == id }),
                  let to = spaces.firstIndex(where: { $0.id == other }) else { return false }
            let current = space
            let moved = spaces.remove(at: from)
            spaces.insert(moved, at: to)
            spaceIndex = spaces.firstIndex { $0 === current } ?? 0
            pagePosition = Double(spaceIndex)

        case .node(let id):
            guard let node = detach(id) else { return false }
            var placed = false
            switch target {
            case .before(let other):
                for profile in profiles where !placed {
                    if case .tab(let tab) = node, let index = profile.favorites.firstIndex(where: { $0.id == other }) {
                        profile.favorites.insert(tab, at: index)
                        placed = true
                    }
                }
                for space in spaces where !placed {
                    if case .tab(let tab) = node, let index = space.today.firstIndex(where: { $0.id == other }) {
                        space.today.insert(tab, at: index)
                        placed = true
                    } else if insert(node, before: other, in: &space.pinned) {
                        placed = true
                    }
                }
            case .intoFolder(let other):
                if let folder = folder(other) {
                    folder.children.append(node)
                    folder.expanded = true
                    placed = true
                }
            case .pinnedEnd(let spaceID):
                if let space = spaces.first(where: { $0.id == spaceID }) {
                    space.pinned.append(node)
                    placed = true
                }
            case .todayStart(let spaceID), .space(let spaceID):
                if case .tab(let tab) = node, let space = spaces.first(where: { $0.id == spaceID }) {
                    space.today.insert(tab, at: 0)
                    placed = true
                }
            case .todayEnd(let spaceID):
                if case .tab(let tab) = node, let space = spaces.first(where: { $0.id == spaceID }) {
                    space.today.append(tab)
                    placed = true
                }
            case .favoritesEnd(let profileID):
                if case .tab(let tab) = node, let profile = profiles.first(where: { $0.id == profileID }) {
                    profile.favorites.append(tab)
                    placed = true
                }
            }
            // Should not happen, but a tab must never vanish because a target went away mid-drag.
            if !placed { space.pinned.append(node) }
        }
        structureChanged()
        return true
    }

    // MARK: Folders

    func newFolder() {
        guard let name = Self.promptText(title: "New Folder", initial: "Untitled Folder", button: "Create") else { return }
        space.pinned.append(.folder(TabFolder(name: name, expanded: true)))
        structureChanged()
    }

    func rename(_ folder: TabFolder) {
        guard let name = Self.promptText(title: "Rename Folder", initial: folder.name, button: "Rename") else { return }
        folder.name = name
        scheduleSave()
    }

    /// Removes the folder and leaves its tabs where the folder was.
    func delete(_ folder: TabFolder) {
        func dissolve(in nodes: inout [Node]) -> Bool {
            if let index = nodes.firstIndex(where: { $0.id == folder.id }) {
                nodes.replaceSubrange(index...index, with: folder.children)
                return true
            }
            for case .folder(let inner) in nodes {
                if dissolve(in: &inner.children) { return true }
            }
            return false
        }
        for space in spaces {
            if dissolve(in: &space.pinned) { break }
        }
        structureChanged()
    }

    static func promptText(title: String, initial: String, button: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let text = field.stringValue.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
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
            swipe.inSidebar = commandBar == nil && panel == nil
                && (sidebarVisible || peeking) && x <= Metrics.sidebarWidth + 6
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
        guard idleSeconds > 0 else { return }
        let now = Date()
        for tab in everyTab where tab.webView != nil && tab !== selectedTab {
            if now.timeIntervalSince(tab.lastActive) > idleSeconds, !tab.isBusy {
                tab.unload()
            }
        }
    }

    var loadedTabCount: Int {
        everyTab.filter { $0.webView != nil }.count
    }

    // MARK: Tabs

    func select(_ tab: BrowserTab) {
        // A favorite belongs to a profile, so it opens in the current space when that space uses the profile.
        let owner: Space
        if let found = space(owning: tab) {
            owner = found
        } else if space.profile === tab.profile {
            owner = space
        } else if let found = spaces.first(where: { $0.profile === tab.profile }) {
            owner = found
        } else {
            return
        }
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
        tab.profile = space.profile
        tab.store = self
        space.today.insert(tab, at: 0)
        if shouldSelect { select(tab) } else { tab.ensureWebView() }
        scheduleSave()
        return tab
    }

    func close(_ tab: BrowserTab) {
        // Each space showing this tab moves to the tab that takes its place in the list.
        let showing = spaces.filter { $0.selected === tab }
        let positions = showing.map { $0.allTabs.firstIndex { $0 === tab } ?? 0 }
        _ = detach(tab.id)
        for (space, position) in zip(showing, positions) {
            let remaining = space.allTabs
            space.selected = remaining.isEmpty ? nil : remaining[min(position, remaining.count - 1)]
            space.selected?.lastActive = Date()
        }
        tab.unload()
        selectedTab?.ensureWebView()
        scheduleSave()
    }

    func closeSelected() {
        if let tab = selectedTab { close(tab) }
    }

    func togglePin(_ tab: BrowserTab) {
        if let owner = space(owning: tab) {
            let pinned = !owner.today.contains { $0 === tab }
            drop(.node(tab.id), on: pinned ? .todayStart(space: owner.id) : .pinnedEnd(space: owner.id))
        } else {
            // A favorite becomes an ordinary pinned tab in the space on screen.
            drop(.node(tab.id), on: .pinnedEnd(space: space.id))
        }
    }

    func isPinned(_ tab: BrowserTab) -> Bool {
        space(owning: tab)?.today.contains(where: { $0 === tab }) == false
    }

    func addToFavorites(_ tab: BrowserTab) {
        guard let profile = tab.profile else { return }
        drop(.node(tab.id), on: .favoritesEnd(profile: profile.id))
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
        if space.selected == nil, let first = space.today.first ?? space.ownTabs.first {
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

    /// Creates a space. Pass a profile to share its cookies and logins, or nil for a fresh one.
    @discardableResult
    func addSpace(name: String, icon: String, theme: SpaceTheme, sharing profile: Profile?) -> Space {
        let owner = profile ?? Profile(name: name)
        if profile == nil { profiles.append(owner) }
        let space = Space(name: name, icon: icon, theme: theme, profile: owner)
        spaces.append(space)
        structureChanged()
        switchSpace(to: spaces.count - 1)
        return space
    }

    func spaces(using profile: Profile) -> [Space] {
        spaces.filter { $0.profile === profile }
    }

    /// Asks first. The last space on a profile can take the profile's cookies and logins with it.
    func confirmDelete(_ space: Space) {
        guard spaces.count > 1 else { return }
        let alert = NSAlert()
        alert.messageText = "Delete \"\(space.name)\"?"
        alert.informativeText = "Its \(space.ownTabs.count) pinned and open tabs go with it."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        let lastOnProfile = spaces(using: space.profile).count == 1
        if lastOnProfile {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Also erase the \"\(space.profile.name)\" profile's cookies and logins"
        }
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        delete(space, eraseProfile: lastOnProfile && alert.suppressionButton?.state == .on)
    }

    func delete(_ space: Space, eraseProfile: Bool) {
        guard spaces.count > 1, let index = spaces.firstIndex(where: { $0 === space }) else { return }
        let current = self.space
        space.ownTabs.forEach { $0.unload() }
        spaces.remove(at: index)
        spaceIndex = spaces.firstIndex { $0 === current } ?? min(index, spaces.count - 1)
        pagePosition = Double(spaceIndex)

        let profile = space.profile
        if eraseProfile, spaces(using: profile).isEmpty {
            profile.favorites.forEach { $0.unload() }
            profiles.removeAll { $0 === profile }
            // WebKit refuses to remove a store that a live page still uses, so give the pages a moment to go.
            let id = profile.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                WKWebsiteDataStore.remove(forIdentifier: id) { error in
                    if let error { NSLog("Cove could not erase the profile: \(error.localizedDescription)") }
                }
            }
        }
        structureChanged()
        if self.space.selected == nil, let first = self.space.today.first ?? self.space.ownTabs.first {
            select(first)
        }
    }

    // MARK: Panels

    func openSpaceEditor(editing space: Space? = nil) {
        commandBar = nil
        panel = .space(SpaceDraft(editing: space))
    }

    func openArcImport() {
        commandBar = nil
        panel = .arcImport(ArcImportDraft(replace: startedFromSeed))
    }

    func openSettings() {
        commandBar = nil
        panel = .settings
    }

    /// Re-attaches or detaches the blocklist on every loaded page to match the current setting.
    func applyBlocking() {
        for tab in everyTab {
            if let webView = tab.webView { ContentBlocker.shared.apply(to: webView) }
        }
    }

    func setBlocking(_ on: Bool) {
        blockingEnabled = on
        ContentBlocker.shared.enabled = on
        applyBlocking()
        scheduleSave()
    }

    /// Changes the tab-sleeping delay and runs a sweep so the new value takes effect at once.
    func setIdle(_ seconds: TimeInterval) {
        idleSeconds = seconds
        unloadIdleTabs()
        scheduleSave()
    }

    /// Unloads every background tab right now, whatever the delay. The settings panel offers this.
    func unloadNow() {
        objectWillChange.send()
        for tab in everyTab where tab.webView != nil && tab !== selectedTab && !tab.isBusy {
            tab.unload()
        }
    }

    /// Loaded tabs, the ones holding memory. Newest use first. The command bar lists these.
    var loadedTabs: [BrowserTab] {
        everyTab.filter { $0.webView != nil }.sorted { $0.lastActive > $1.lastActive }
    }

    /// Sleeps one tab: frees its page but leaves it in the sidebar to reopen later.
    func sleep(_ tab: BrowserTab) {
        guard tab.webView != nil, tab !== selectedTab else { return }
        objectWillChange.send()
        tab.unload()
    }

    func closePanel() {
        panel = nil
        focusWeb()
    }

    func save(_ draft: SpaceDraft) {
        let name = draft.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if let space = draft.editing {
            space.name = name
            space.icon = draft.icon
            space.theme = draft.theme
            revision += 1
            scheduleSave()
        } else {
            addSpace(name: name, icon: draft.icon, theme: draft.theme,
                     sharing: profiles.first { $0.id == draft.profileID })
        }
        closePanel()
    }

    // MARK: Command bar

    func openCommandBar(_ mode: CommandBarMode) {
        guard panel == nil else { return }
        query = mode == .editURL ? (selectedTab?.url.absoluteString ?? "") : ""
        highlight = 0
        showingActiveTabs = false
        commandBar = mode
    }

    func closeCommandBar() {
        commandBar = nil
        showingActiveTabs = false
        focusWeb()
    }

    var suggestions: [Suggestion] {
        let text = query.trimmingCharacters(in: .whitespaces)
        let tabs = space.allTabs
        let loaded = loadedTabs.count
        if text.isEmpty {
            // A short list of what is open, plus the Active Tabs command as a discoverable entry.
            let open = (space.today + space.pinned.flatMap(\.tabs) + space.profile.favorites)
                .filter { $0 !== selectedTab }.prefix(4).map { Suggestion.tab($0) }
            return Array(open) + (loaded > 0 ? [.activeTabs(loaded)] : [])
        }
        let needle = text.lowercased()
        let matches = tabs.filter {
            $0.title.lowercased().contains(needle) || $0.host.lowercased().contains(needle)
        }
        let (url, isSearch) = Self.resolve(text)
        let label = isSearch ? text : (url.host ?? text)
        // Searching "active tabs" (or a piece of it) surfaces the command to drill in.
        let command: [Suggestion] = (loaded > 0 && "active tabs".contains(needle)) ? [.activeTabs(loaded)] : []
        let openMatches = matches.prefix(4).map { Suggestion.tab($0) }
        // Visited pages that are not already an open tab, ranked by the history store.
        let openURLs = Set(tabs.map(\.url))
        let fromHistory = history.matches(text, profile: space.profile.id, limit: 5)
            .filter { !openURLs.contains($0.url) }
            .map { Suggestion.go($0.url, $0.title, isSearch: false) }
        return command + [.go(url, label, isSearch: isSearch)] + openMatches + fromHistory
    }

    /// Loaded tabs matching the filter typed inside the active-tabs sub-view.
    var activeMatches: [BrowserTab] {
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return loadedTabs }
        return loadedTabs.filter { $0.title.lowercased().contains(text) || $0.host.lowercased().contains(text) }
    }

    /// Closes the highlighted tab in the sub-view, then keeps the highlight in range.
    func closeActiveTab(at index: Int) {
        let list = activeMatches
        guard list.indices.contains(index) else { return }
        close(list[index])
        highlight = min(highlight, max(activeMatches.count - 1, 0))
    }

    /// Sleeps the highlighted tab in the sub-view, unless it is the one on screen.
    func sleepActiveTab(at index: Int) {
        let list = activeMatches
        guard list.indices.contains(index), list[index] !== selectedTab else { return }
        sleep(list[index])
        highlight = min(highlight, max(activeMatches.count - 1, 0))
    }

    func submit() {
        if showingActiveTabs {
            let list = activeMatches
            let tab = list.indices.contains(highlight) ? list[highlight] : list.first
            if let tab { select(tab); closeCommandBar() }
            return
        }
        let list = suggestions
        guard list.indices.contains(highlight) else { closeCommandBar(); return }
        run(list[highlight])
    }

    func run(_ suggestion: Suggestion) {
        if case .activeTabs = suggestion {
            // Enter the sub-view instead of closing. The filter field starts empty.
            query = ""
            highlight = 0
            showingActiveTabs = true
            return
        }
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
        case .activeTabs:
            break
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

    // MARK: Saving

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
        SessionFile.save(self)
    }

    // MARK: Seed data

    private static func tab(_ title: String, _ address: String) -> BrowserTab {
        BrowserTab(title: title, url: URL(string: address)!)
    }

    private static func seed() -> ([Profile], [Space]) {
        // Fixed profile ids, so logins survive a relaunch.
        let personalProfile = Profile(
            name: "Personal", id: UUID(uuidString: "6F1E7C1A-0B5D-4C3E-9A41-1D2B3C4D5E01")!,
            favorites: [
                tab("Gmail", "https://mail.google.com"),
                tab("YouTube", "https://www.youtube.com"),
                tab("Netflix", "https://www.netflix.com"),
                tab("Spotify", "https://open.spotify.com"),
                tab("X", "https://x.com"),
                tab("GitHub", "https://github.com"),
            ]
        )
        let workProfile = Profile(
            name: "Work", id: UUID(uuidString: "6F1E7C1A-0B5D-4C3E-9A41-1D2B3C4D5E02")!,
            favorites: [
                tab("Gmail", "https://mail.google.com"),
                tab("Linear", "https://linear.app"),
                tab("Notion", "https://www.notion.so"),
            ]
        )
        let personal = Space(
            name: "Personal", icon: "leaf.fill", theme: SpaceTheme(hue: 0.72), profile: personalProfile,
            pinned: [
                .tab(tab("Hacker News", "https://news.ycombinator.com")),
                .tab(tab("Figma", "https://www.figma.com")),
                .folder(TabFolder(name: "Reading", children: [
                    .tab(tab("WebKit Blog", "https://webkit.org/blog/")),
                    .tab(tab("MDN Web Docs", "https://developer.mozilla.org")),
                ])),
            ],
            today: [
                tab("Wikipedia", "https://www.wikipedia.org"),
                tab("Apple", "https://www.apple.com"),
            ]
        )
        let work = Space(
            name: "Work", icon: "briefcase.fill", theme: SpaceTheme(hue: 0.56), profile: workProfile,
            pinned: [.tab(tab("GitHub", "https://github.com"))],
            today: [tab("Can I use", "https://caniuse.com")]
        )
        return ([personalProfile, workProfile], [personal, work])
    }
}
