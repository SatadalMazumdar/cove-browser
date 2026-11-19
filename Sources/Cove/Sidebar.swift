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
            IconButton(symbol: "archivebox") {}
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
        SpaceIcon(icon: space.icon)
            .foregroundStyle(theme.text)
            .opacity(0.3 + 0.6 * nearness)
            .scaleEffect(1 + 0.12 * nearness)
            .frame(width: 26, height: 26)
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
                store.window?.zoom(nil)
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
            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(profile.favorites) { tab in
                    FavoriteTile(tab: tab, store: store, isSelected: selected === tab,
                                 marked: store.dropTarget == .before(tab.id))
                }
            }
            .padding(.bottom, 10)
        }
    }
}

// MARK: - Drag and drop

/// Sidebar drags carry this type, so text dragged out of a web page never counts as a tab.
let coveDragType = "dev.prototype.cove.item"

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
            provider.registerDataRepresentation(forTypeIdentifier: coveDragType, visibility: .ownProcess) { done in
                done(Data(), nil)
                return nil
            }
            return provider
        }
    }

    func dropTarget(_ target: DropTarget, store: BrowserStore) -> some View {
        onDrop(of: [coveDragType], delegate: SidebarDrop(store: store, target: target))
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

    var body: some View {
        Button { store.openCommandBar(.editURL) } label: {
            HStack(spacing: 6) {
                if let tab {
                    HostLabel(tab: tab)
                } else {
                    Text("Search or Enter URL...").foregroundStyle(theme.secondary)
                }
                Spacer(minLength: 0)
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

    var body: some View {
        IconButton(symbol: "arrow.left", enabled: tab.canGoBack) { tab.webView?.goBack() }
        IconButton(symbol: "arrow.right", enabled: tab.canGoForward) { tab.webView?.goForward() }
        IconButton(symbol: tab.isLoading ? "xmark" : "arrow.clockwise") {
            if tab.isLoading { tab.webView?.stopLoading() } else { tab.webView?.reload() }
        }
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
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(isSelected ? theme.selected : (hover ? theme.text.opacity(0.13) : theme.pill))
            .shadow(color: isSelected ? theme.selectedShadow : .clear, radius: 2, y: 1)
            .frame(height: 48)
            .overlay { FaviconView(tab: tab, size: 18) }
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
