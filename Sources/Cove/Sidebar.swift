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
                    // Brightness follows the swipe, so the icons cross-fade under the fingers.
                    let nearness = max(0, 1 - abs(store.pagePosition - Double(index)))
                    Button { store.switchSpace(to: index) } label: {
                        Image(systemName: item.symbol)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.text.opacity(0.3 + 0.6 * nearness))
                            .scaleEffect(1 + 0.12 * nearness)
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(item.name)
                }
            }
            Spacer()
            IconButton(symbol: "plus") { store.openCommandBar(.newTab) }
        }
        .frame(height: 40)
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
                if !floating { Spacer().frame(width: 62) }
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

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 2) {
                favorites
                spaceTitle
                ForEach(space.pinned) { tab in row(tab) }
                ForEach(space.folders) { folder in
                    FolderView(folder: folder, store: store, selected: space.selected)
                }
                divider
                newTabRow
                ForEach(space.today) { tab in row(tab) }
            }
            .padding(.top, 10)
            .padding(.horizontal, Metrics.gutter)
        }
    }

    private func row(_ tab: BrowserTab) -> some View {
        TabRow(tab: tab, store: store, isSelected: space.selected === tab)
    }

    @ViewBuilder private var favorites: some View {
        if !space.favorites.isEmpty {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(space.favorites) { tab in
                    FavoriteTile(tab: tab, store: store, isSelected: space.selected === tab)
                }
            }
            .padding(.bottom, 10)
        }
    }

    private var spaceTitle: some View {
        HStack(spacing: 7) {
            Image(systemName: space.symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(space.name)
                .font(.system(size: 12, weight: .semibold))
            Spacer()
        }
        .foregroundStyle(theme.secondary)
        .padding(.horizontal, 10)
        .frame(height: 28)
    }

    private var divider: some View {
        HStack(spacing: 8) {
            Rectangle().fill(theme.faint).frame(height: 1)
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
    let isSelected: Bool
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
        .contextMenu {
            Button(store.isPinned(tab) ? "Unpin Tab" : "Pin Tab") { store.togglePin(tab) }
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
    @Environment(\.theme) private var theme
    @Local private var hover = false

    var body: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(isSelected ? theme.selected : (hover ? theme.text.opacity(0.13) : theme.pill))
            .shadow(color: isSelected ? theme.selectedShadow : .clear, radius: 2, y: 1)
            .frame(height: 48)
            .overlay { FaviconView(tab: tab, size: 18) }
            .contentShape(Rectangle())
            .onTapGesture { store.select(tab) }
            .onHover { hover = $0 }
            .help(tab.title)
            .contextMenu {
                Button("Remove from Favorites") { store.close(tab) }
            }
    }
}

private struct FolderView: View {
    @ObservedObject var folder: TabFolder
    let store: BrowserStore
    let selected: BrowserTab?
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 2) {
            HoverRow(action: { withAnimation(.easeOut(duration: 0.16)) { folder.expanded.toggle() } }) {
                HStack(spacing: 9) {
                    Image(systemName: folder.expanded ? "folder.fill" : "folder")
                        .font(.system(size: 13))
                        .frame(width: 16, height: 16)
                    Text(folder.name).font(.system(size: 13))
                    Spacer()
                }
                .foregroundStyle(theme.text.opacity(0.78))
                .padding(.horizontal, 10)
            }
            if folder.expanded {
                ForEach(folder.tabs) { tab in
                    TabRow(tab: tab, store: store, isSelected: selected === tab)
                        .padding(.leading, 16)
                }
            }
        }
    }
}
