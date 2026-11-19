import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: BrowserStore
    /// The floating sidebar has no traffic lights, so it does not reserve room for them.
    var floating = false
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            SidebarHeader(store: store, space: store.space, floating: floating)
                .padding(.horizontal, Metrics.gutter)

            // Every space sits side by side in one strip. A two-finger swipe moves the strip
            // with the fingers, so the next space is already on screen as it slides in.
            GeometryReader { geo in
                HStack(alignment: .top, spacing: 0) {
                    ForEach(store.spaces) { space in
                        SpaceColumn(store: store, space: space)
                            .frame(width: geo.size.width, height: geo.size.height)
                    }
                }
                .offset(x: -store.pagePosition * geo.size.width)
            }
            .clipped()

            bottomBar
                .padding(.horizontal, Metrics.gutter)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            DownloadsButton(store: store)
            Spacer()
            HStack(spacing: 4) {
                ForEach(Array(store.spaces.enumerated()), id: \.element.id) { index, item in
                    SpaceButton(store: store, space: item, index: index,
                                marked: store.dropTarget == .space(item.id))
                }
            }
            Spacer()
            Menu {
                Button("New Tab") { store.openCommandBar(.newTab) }
                Button("New Folder") { store.newFolder() }
                Button("New Space...") { store.openSpaceEditor() }
                Divider()
                Button("Import from Arc...") { store.openArcImport() }
                Divider()
                Button("Settings...") { store.openSettings() }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.text.opacity(0.7))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 28, height: 26)
        }
        .frame(height: 40)
    }
}

/// One space's icon in the bottom bar. Click to switch, drag to reorder, drop a tab on it to move the tab.
private struct SpaceButton: View {
    let store: BrowserStore
    @ObservedObject var space: Space
    let index: Int
    let marked: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        // Brightness follows the swipe, so the icons cross-fade under the fingers.
        let nearness = max(0, 1 - abs(store.pagePosition - Double(index)))
        SpaceIcon(icon: space.icon, size: 11)
            .foregroundStyle(theme.text)
            .opacity(0.3 + 0.6 * nearness)
            .scaleEffect(1 + 0.12 * nearness)
            .frame(width: 22, height: 22)
            .background(marked ? theme.text.opacity(0.18) : .clear,
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { store.switchSpace(to: index) }
            .help(space.name)
            .dragSource(.space(space.id), store: store)
            .dropTarget(.space(space.id), store: store)
            .contextMenu { SpaceMenu(store: store, space: space) }
    }
}

private struct SpaceMenu: View {
    let store: BrowserStore
    let space: Space

    var body: some View {
        Button("Edit Space...") { store.openSpaceEditor(editing: space) }
        Button("New Space...") { store.openSpaceEditor() }
        Divider()
        Button("Delete Space...") { store.confirmDelete(space) }
            .disabled(store.spaces.count < 2)
    }
}

/// Close, minimize and zoom, drawn to match the system buttons. Used in the floating sidebar,
/// where the window's own traffic lights are hidden. The symbols appear on hover, as they do natively.
private struct WindowControls: View {
    let store: BrowserStore
    @Local private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            dot(Color(red: 1, green: 0.37, blue: 0.34), "xmark") { store.window?.performClose(nil) }
            dot(Color(red: 0.99, green: 0.74, blue: 0.18), "minus") { store.window?.miniaturize(nil) }
            dot(Color(red: 0.16, green: 0.78, blue: 0.25), "arrow.up.left.and.arrow.down.right") {
                store.window?.toggleFullScreen(nil)
            }
        }
        .padding(.leading, 4)
        .onHover { hover = $0 }
    }

    private func dot(_ color: Color, _ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .overlay {
                    if hover {
                        Image(systemName: symbol)
                            .font(.system(size: 7, weight: .black))
                            .foregroundStyle(.black.opacity(0.55))
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// The part of the sidebar that stays put during a swipe: window controls and the URL pill.
private struct SidebarHeader: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var space: Space
    let floating: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 2) {
                // The real traffic lights hide with the sidebar. The floating sidebar draws its own
                // in the same spot, so close, minimize and zoom stay reachable while it is open.
                if floating {
                    WindowControls(store: store).frame(width: 62, alignment: .leading)
                } else {
                    Spacer().frame(width: 62)
                }
                IconButton(symbol: "sidebar.left") { store.sidebarVisible.toggle() }
                Spacer()
                if let tab = space.selected {
                    NavButtons(tab: tab)
                } else {
                    IconButton(symbol: "arrow.left", enabled: false) {}
                    IconButton(symbol: "arrow.right", enabled: false) {}
                    IconButton(symbol: "arrow.clockwise", enabled: false) {}
                }
            }
            .frame(height: 28)
            URLPill(store: store, tab: space.selected)
        }
    }
}

/// One space's favorites, pinned tabs, folders and today's tabs.
private struct SpaceColumn: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var space: Space
    @Environment(\.theme) private var theme
    @Local private var dividerHover = false
    @Local private var titleHover = false
    /// How far from each edge the list is scrolled. The fade at an edge grows in only once there
    /// is content past it, so a short list at rest has no fade and no hard clip.
    @Local private var topFade: CGFloat = 0
    @Local private var bottomFade: CGFloat = 0
    private let fadeHeight: CGFloat = 24

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 2) {
                FavoritesGrid(store: store, profile: space.profile, selected: space.selected)
                spaceTitle
                if !space.pinnedCollapsed {
                    ForEach(space.pinned) { node in
                        NodeRow(node: node, store: store, space: space, depth: 0)
                    }
                }
                divider
                newTabRow
                ForEach(space.today) { tab in
                    TabRow(tab: tab, store: store, space: space, isSelected: space.selected === tab,
                           marked: store.dropTarget == .before(tab.id))
                }
                // Room under the last tab, so a drag can land at the end of the list.
                Color.clear
                    .frame(height: 80)
                    .contentShape(Rectangle())
                    .dropTarget(.todayEnd(space: space.id), store: store)
            }
            .padding(.top, 10)
            .padding(.horizontal, Metrics.gutter)
        }
        .modifier(EdgeFadeTracker(top: $topFade, bottom: $bottomFade, limit: fadeHeight))
        .mask(
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                    .frame(height: topFade)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: bottomFade)
            }
        )
    }

    private func toggleCollapsed() {
        withAnimation(.easeOut(duration: 0.18)) { space.pinnedCollapsed.toggle() }
        store.scheduleSave()
    }

    private var spaceTitle: some View {
        let count = space.pinned.reduce(0) { $0 + $1.tabs.count }
        // A Button handles the click. onTapGesture on a row that also owns a drop target and a
        // context menu was being swallowed, so the header looked dead.
        return Button(action: toggleCollapsed) {
            HStack(spacing: 7) {
                if !space.pinned.isEmpty {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .rotationEffect(.degrees(space.pinnedCollapsed ? 0 : 90))
                        .foregroundStyle(theme.text.opacity(titleHover ? 0.75 : 0.45))
                        .frame(width: 10)
                }
                SpaceIcon(icon: space.icon, size: 11)
                Text(space.name)
                    .font(.system(size: 12, weight: .semibold))
                // When collapsed, a count hints at what is folded away.
                if space.pinnedCollapsed && count > 0 {
                    Text("\(count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(theme.text.opacity(0.4))
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(theme.secondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .frame(maxWidth: .infinity)
            .background(titleHover ? theme.hover : .clear,
                        in: RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { titleHover = $0 }
        .contextMenu {
            Button(space.pinnedCollapsed ? "Expand Pinned Tabs" : "Collapse Pinned Tabs") {
                withAnimation(.easeOut(duration: 0.18)) { space.pinnedCollapsed.toggle() }
                store.scheduleSave()
            }
            Divider()
            SpaceMenu(store: store, space: space)
            Divider()
            Button("New Folder") { store.newFolder() }
        }
        .dropTarget(space.pinned.first.map { .before($0.id) } ?? .pinnedEnd(space: space.id), store: store)
    }

    private var divider: some View {
        let marked = store.dropTarget == .pinnedEnd(space: space.id)
        return HStack(spacing: 8) {
            Rectangle().fill(marked ? theme.accent : theme.faint).frame(height: marked ? 2 : 1)
            if dividerHover && !space.today.isEmpty {
                Button("Clear") { store.clearToday() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.secondary)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 18)
        .contentShape(Rectangle())
        .onHover { dividerHover = $0 }
        .dropTarget(.pinnedEnd(space: space.id), store: store)
    }

    private var newTabRow: some View {
        HoverRow(action: { store.openCommandBar(.newTab) }) {
            HStack(spacing: 9) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16, height: 16)
                Text("New Tab").font(.system(size: 13))
                Spacer()
            }
            .foregroundStyle(theme.secondary)
            .padding(.horizontal, 10)
        }
        .insertionMark(store.dropTarget == .todayStart(space: space.id), edge: .bottom)
        .dropTarget(.todayStart(space: space.id), store: store)
    }
}

/// The profile's favorites. Every space on the profile shows the same grid.
private struct FavoritesGrid: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var profile: Profile
    let selected: BrowserTab?

    var body: some View {
        if !profile.favorites.isEmpty {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 4)
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(profile.favorites) { tab in
                    FavoriteTile(tab: tab, store: store, isSelected: selected === tab,
                                 marked: store.dropTarget == .before(tab.id))
                }
            }
            .padding(.bottom, 8)
        }
    }
}

// MARK: - Drag and drop

/// Sidebar drags carry this type, so text dragged out of a web page never counts as a tab.
let cloveDragType = "dev.clove.browser.item"

private struct SidebarDrop: DropDelegate {
    let store: BrowserStore
    let target: DropTarget

    func validateDrop(info: DropInfo) -> Bool { store.canDrop(on: target) }
    func dropEntered(info: DropInfo) { if store.canDrop(on: target) { store.dropTarget = target } }
    func dropExited(info: DropInfo) { if store.dropTarget == target { store.dropTarget = nil } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        guard let item = store.dragging else { return false }
        return store.drop(item, on: target)
    }
}

extension View {
    func dragSource(_ item: DragItem, store: BrowserStore) -> some View {
        onDrag {
            store.dragging = item
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: cloveDragType, visibility: .ownProcess) { done in
                done(Data(), nil)
                return nil
            }
            return provider
        }
    }

    func dropTarget(_ target: DropTarget, store: BrowserStore) -> some View {
        onDrop(of: [cloveDragType], delegate: SidebarDrop(store: store, target: target))
    }

    /// The line that shows where a dragged row will land.
    func insertionMark(_ shown: Bool, edge: VerticalEdge = .top) -> some View {
        overlay(alignment: edge == .top ? .top : .bottom) {
            if shown {
                Capsule().fill(Color.accentColor).frame(height: 2).padding(.horizontal, 6)
                    .offset(y: edge == .top ? -2 : 2)
            }
        }
    }
}

// MARK: - URL pill

private struct URLPill: View {
    @ObservedObject var store: BrowserStore
    var tab: BrowserTab?
    @Environment(\.theme) private var theme
    @Local private var hover = false
    @Local private var copied = false

    var body: some View {
        Button { store.openCommandBar(.editURL) } label: {
            HStack(spacing: 6) {
                if let tab {
                    HostLabel(tab: tab)
                } else {
                    Text("Search or Enter URL...").foregroundStyle(theme.secondary)
                }
                Spacer(minLength: 0)
                // A copy button appears on hover, ticks green for a moment after a copy.
                if tab != nil, hover || copied {
                    Button(action: copy) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(copied ? theme.accent : theme.secondary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Copy URL")
                }
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondary)
            }
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(theme.pill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .contextMenu {
            if let tab {
                Button("Copy URL", action: copy)
                Button("Paste and Go") {
                    if let text = NSPasteboard.general.string(forType: .string) {
                        store.query = text
                        store.openCommandBar(.editURL)
                        store.submit()
                    }
                }
                Divider()
                let host = tab.host
                Button(store.blockingOn(for: host) ? "Turn Off Blocking for \(host)" : "Turn On Blocking for \(host)") {
                    store.toggleBlocking(forHost: host)
                }
                .disabled(!store.blockingEnabled)
            }
        }
    }

    private func copy() {
        guard let url = tab?.url else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { copied = false }
    }
}

private struct HostLabel: View {
    @ObservedObject var tab: BrowserTab
    @Environment(\.theme) private var theme

    var body: some View {
        Text(tab.host)
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(theme.primary)
    }
}

// MARK: - Navigation buttons

private struct NavButtons: View {
    @ObservedObject var tab: BrowserTab
    @Environment(\.theme) private var theme

    var body: some View {
        IconButton(symbol: "arrow.left", enabled: tab.canGoBack) { tab.webView?.goBack() }
        IconButton(symbol: "arrow.right", enabled: tab.canGoForward) { tab.webView?.goForward() }
        IconButton(symbol: tab.isLoading ? "xmark" : "arrow.clockwise") {
            if tab.isLoading { tab.webView?.stopLoading() } else { tab.webView?.reload() }
        }
        Button { tab.toggleReader() } label: {
            Image(systemName: "doc.plaintext")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(tab.readerMode ? theme.accent : theme.text.opacity(0.7))
                .frame(width: 28, height: 26)
                .background(tab.readerMode ? theme.accent.opacity(0.18) : .clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Reader mode")
    }
}

struct IconButton: View {
    let symbol: String
    var enabled = true
    let action: () -> Void
    @Environment(\.theme) private var theme
    @Local private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(enabled ? theme.text.opacity(0.7) : theme.text.opacity(0.25))
                .frame(width: 28, height: 26)
                .background(hover && enabled ? theme.hover : .clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hover = $0 }
    }
}

// MARK: - Rows

/// A full-width row that highlights under the pointer.
private struct HoverRow<Content: View>: View {
    var isSelected = false
    let action: () -> Void
    @ViewBuilder var content: (Bool) -> Content
    @Environment(\.theme) private var theme
    @Local private var hover = false

    init(isSelected: Bool = false, action: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.isSelected = isSelected
        self.action = action
        self.content = { _ in content() }
    }

    init(isSelected: Bool = false, action: @escaping () -> Void, @ViewBuilder hoverContent: @escaping (Bool) -> Content) {
        self.isSelected = isSelected
        self.action = action
        self.content = hoverContent
    }

    var body: some View {
        content(hover)
            .frame(height: Metrics.rowHeight)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: Metrics.rowRadius, style: .continuous)
                    .fill(isSelected ? theme.selected : (hover ? theme.hover : .clear))
                    .shadow(color: isSelected ? theme.selectedShadow : .clear, radius: 2, y: 1)
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .onHover { hover = $0 }
    }
}

struct TabRow: View {
    @ObservedObject var tab: BrowserTab
    let store: BrowserStore
    let space: Space
    let isSelected: Bool
    var marked = false
    @Environment(\.theme) private var theme

    var body: some View {
        HoverRow(isSelected: isSelected, action: { store.select(tab) }, hoverContent: { hover in
            HStack(spacing: 9) {
                FaviconView(tab: tab)
                FadingTitle(text: tab.title)
                    .foregroundStyle(isSelected ? theme.primary : theme.text.opacity(0.78))
                if hover {
                    Button { store.close(tab) } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(theme.secondary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
        })
        .insertionMark(marked)
        .dragSource(.node(tab.id), store: store)
        .dropTarget(.before(tab.id), store: store)
        .contextMenu {
            Button(store.isPinned(tab) ? "Unpin Tab" : "Pin Tab") { store.togglePin(tab) }
            Button("Add to Favorites") { store.addToFavorites(tab) }
            let folders = space.folders
            if !folders.isEmpty {
                Menu("Move to Folder") {
                    ForEach(folders) { folder in
                        Button(folder.name) { store.drop(.node(tab.id), on: .intoFolder(folder.id)) }
                    }
                }
            }
            let others = store.spaces.filter { $0 !== space }
            if !others.isEmpty {
                Menu("Move to Space") {
                    ForEach(others) { other in
                        Button(other.name) { store.drop(.node(tab.id), on: .space(other.id)) }
                    }
                }
            }
            Button("Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(tab.url.absoluteString, forType: .string)
            }
            Divider()
            Button("Close Tab") { store.close(tab) }
        }
    }
}

/// Long titles fade out at the right edge instead of ending in an ellipsis.
private struct FadingTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            // minWidth 0 lets the row shrink below the text's width. Without it one long
            // title widens the whole column and pushes the sidebar's content off both edges.
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .clipped()
            .mask {
                LinearGradient(stops: [.init(color: .black, location: 0.86), .init(color: .clear, location: 1)],
                               startPoint: .leading, endPoint: .trailing)
            }
    }
}

struct FaviconView: View {
    @ObservedObject var tab: BrowserTab
    var size: CGFloat = 16
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if let icon = tab.favicon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            } else {
                Image(systemName: "globe")
                    .resizable()
                    .foregroundStyle(theme.secondary)
            }
        }
        .frame(width: size, height: size)
        .opacity(tab.isLoading ? 0.45 : 1)
    }
}

private struct FavoriteTile: View {
    @ObservedObject var tab: BrowserTab
    let store: BrowserStore
    let isSelected: Bool
    let marked: Bool
    @Environment(\.theme) private var theme
    @Local private var hover = false

    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(isSelected ? theme.selected : (hover ? theme.text.opacity(0.13) : theme.pill))
            .shadow(color: isSelected ? theme.selectedShadow : .clear, radius: 2, y: 1)
            .frame(height: 38)
            .overlay { FaviconView(tab: tab, size: 16) }
            .overlay(alignment: .leading) {
                if marked { Capsule().fill(Color.accentColor).frame(width: 2).padding(.vertical, 6).offset(x: -4) }
            }
            .contentShape(Rectangle())
            .onTapGesture { store.select(tab) }
            .onHover { hover = $0 }
            .help(tab.title)
            .dragSource(.node(tab.id), store: store)
            .dropTarget(.before(tab.id), store: store)
            .contextMenu {
                Button("Move to Pinned Tabs") { store.togglePin(tab) }
                Button("Remove from Favorites") { store.close(tab) }
            }
    }
}

/// A tab row or a folder, at any depth in the pinned area.
private struct NodeRow: View {
    let node: Node
    @ObservedObject var store: BrowserStore
    @ObservedObject var space: Space
    let depth: Int

    var body: some View {
        switch node {
        case .tab(let tab):
            TabRow(tab: tab, store: store, space: space, isSelected: space.selected === tab,
                   marked: store.dropTarget == .before(tab.id))
                .padding(.leading, CGFloat(depth) * 14)
        case .folder(let folder):
            FolderView(folder: folder, store: store, space: space, depth: depth)
        }
    }
}

private struct FolderView: View {
    @ObservedObject var folder: TabFolder
    @ObservedObject var store: BrowserStore
    let space: Space
    let depth: Int
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 2) {
            HoverRow(isSelected: store.dropTarget == .intoFolder(folder.id),
                     action: { withAnimation(.easeOut(duration: 0.16)) { folder.expanded.toggle() } }) {
                HStack(spacing: 9) {
                    Image(systemName: folder.expanded ? "folder.fill" : "folder")
                        .font(.system(size: 13))
                        .frame(width: 16, height: 16)
                    Text(folder.name).font(.system(size: 13)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(theme.text.opacity(0.78))
                .padding(.horizontal, 10)
            }
            .padding(.leading, CGFloat(depth) * 14)
            .dragSource(.node(folder.id), store: store)
            .dropTarget(.intoFolder(folder.id), store: store)
            .contextMenu {
                Button("Rename Folder...") { store.rename(folder) }
                Button("Delete Folder, Keep Tabs") { store.delete(folder) }
            }
            if folder.expanded {
                ForEach(folder.children) { child in
                    NodeRow(node: child, store: store, space: space, depth: depth + 1)
                }
            }
        }
    }
}

/// Reports how far the list can still scroll past each edge, so the fades track it reliably.
/// Uses the scroll geometry API on macOS 15 and later; below that the fades stay off.
private struct EdgeFadeTracker: ViewModifier {
    @Binding var top: CGFloat
    @Binding var bottom: CGFloat
    let limit: CGFloat

    private struct Edges: Equatable { var top: CGFloat; var bottom: CGFloat }

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.onScrollGeometryChange(for: Edges.self) { geo in
                Edges(top: geo.contentOffset.y,
                      bottom: geo.contentSize.height - geo.contentOffset.y - geo.containerSize.height)
            } action: { _, edges in
                withAnimation(.easeOut(duration: 0.12)) {
                    top = min(max(edges.top, 0), limit)
                    bottom = min(max(edges.bottom, 0), limit)
                }
            }
        } else {
            content
        }
    }
}

// MARK: - Downloads

/// The archive icon in the bottom bar. Shows a dot while downloading, and a popover with the list.
private struct DownloadsButton: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var downloads: DownloadManager
    @Environment(\.theme) private var theme
    @Local private var open = false

    init(store: BrowserStore) {
        self.store = store
        self.downloads = store.downloads
    }

    var body: some View {
        Button { open.toggle() } label: {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.text.opacity(0.7))
                .frame(width: 28, height: 26)
                .overlay(alignment: .topTrailing) {
                    if downloads.hasActive {
                        Circle().fill(theme.accent).frame(width: 6, height: 6).offset(x: -2, y: 2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Downloads")
        .popover(isPresented: $open, arrowEdge: .top) {
            DownloadsList(downloads: downloads).frame(width: 300)
        }
    }
}

private struct DownloadsList: View {
    @ObservedObject var downloads: DownloadManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Downloads").font(.system(size: 13, weight: .semibold))
                Spacer()
                if downloads.items.contains(where: { $0.state != .running }) {
                    Button("Clear") { downloads.clearFinished() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
            if downloads.items.isEmpty {
                Text("Nothing downloaded yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(14)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(downloads.items) { item in
                            DownloadRow(item: item, downloads: downloads)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
    }
}

private struct DownloadRow: View {
    @ObservedObject var item: DownloadItem
    let downloads: DownloadManager

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.filename).font(.system(size: 12)).lineLimit(1)
                if item.state == .running {
                    ProgressView(value: item.fraction).controlSize(.small)
                } else {
                    Text(item.state == .finished ? "Done" : "Failed")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if item.state == .finished {
                Button { downloads.reveal(item) } label: {
                    Image(systemName: "magnifyingglass").font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var icon: String {
        switch item.state {
        case .running: return "arrow.down.circle"
        case .finished: return "doc"
        case .failed: return "exclamationmark.triangle"
        }
    }
}
