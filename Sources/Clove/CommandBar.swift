import SwiftUI

/// The floating search and address panel. Cmd+T opens it empty, Cmd+L opens it on the current URL.
struct CommandBar: View {
    @ObservedObject var store: BrowserStore
    @Environment(\.theme) private var theme
    @FocusState private var focused: Bool
    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.12)
                .contentShape(Rectangle())
                .onTapGesture { store.closeCommandBar() }

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    if store.showingActiveTabs {
                        Button { store.showingActiveTabs = false; store.query = "" } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.6))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    TextField(store.showingActiveTabs ? "Filter active tabs..." : "Search or Enter URL...",
                              text: $store.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 19))
                        .foregroundStyle(.white)
                        .focused($focused)
                        .onSubmit { store.submit() }
                }
                .padding(.horizontal, 18)
                .frame(height: 58)

                if store.showingActiveTabs {
                    activeTabsView
                } else {
                    let items = store.suggestions
                    if !items.isEmpty {
                        Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
                        VStack(spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                SuggestionRow(item: item, isHighlighted: index == store.highlight)
                                    .onTapGesture { store.run(item) }
                                    .onHover { if $0 { store.highlight = index } }
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .frame(width: 680)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hue: theme.hue, saturation: 0.25, brightness: 0.13))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.45), radius: 40, y: 18)
            }
            .padding(.top, 130)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { DispatchQueue.main.async { focused = true } }
        .onChange(of: store.query) { _, _ in store.highlight = 0 }
    }

    private var activeTabsView: some View {
        let tabs = store.activeMatches
        return VStack(spacing: 0) {
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                            ActiveTabRow(tab: tab, store: store,
                                         isCurrent: tab === store.selectedTab,
                                         isHighlighted: index == store.highlight)
                                .id(index)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 360)
                .onChange(of: store.highlight) { _, h in
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(h, anchor: .center) }
                }
            }
            // Keyboard hints, so the actions are discoverable without a mouse.
            HStack(spacing: 16) {
                shortcutHint("return", "Switch")
                shortcutHint("command return", "Sleep")
                shortcutHint("command delete.left", "Close")
                Spacer()
                Button("Sleep all") { store.unloadNow() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(theme.accent)
            }
            .padding(.horizontal, 16)
            .frame(height: 34)
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.06)).frame(height: 1) }
        }
    }

    private func shortcutHint(_ symbols: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            ForEach(symbols.split(separator: " ").map(String.init), id: \.self) { s in
                Image(systemName: s)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(width: 18, height: 16)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            Text(label).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45))
        }
    }
}

/// One loaded tab in the command bar, with switch, sleep and close.
private struct ActiveTabRow: View {
    @ObservedObject var tab: BrowserTab
    let store: BrowserStore
    let isCurrent: Bool
    var isHighlighted = false
    @Environment(\.theme) private var theme
    @Local private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            FaviconView(tab: tab, size: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(tab.title).font(.system(size: 13)).foregroundStyle(.white.opacity(0.92)).lineLimit(1)
                Text(tab.host).font(.system(size: 11)).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
            }
            Spacer(minLength: 8)
            if isCurrent {
                Text("on screen").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.4))
            } else {
                Button { store.sleep(tab) } label: {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Sleep this tab, keep it in the sidebar")
            }
            Button { store.close(tab) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close this tab")
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(isHighlighted ? theme.accent.opacity(0.55) : (hover ? theme.accent.opacity(0.3) : .white.opacity(0.03)),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { store.select(tab); store.closeCommandBar() }
        .onHover { hover = $0 }
    }
}

private struct SuggestionRow: View {
    let item: Suggestion
    let isHighlighted: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 26, height: 26)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
            Spacer()
            Text(hint)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(isHighlighted ? 0.75 : 0.35))
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .background(isHighlighted ? theme.accent.opacity(0.55) : .clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
    }

    @ViewBuilder private var icon: some View {
        switch item {
        case .tab(let tab):
            FaviconView(tab: tab, size: 16)
        case .go(_, _, let isSearch):
            Image(systemName: isSearch ? "magnifyingglass" : "globe")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        case .activeTabs:
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var title: String {
        switch item {
        case .tab(let tab): return tab.title
        case .go(_, let label, _): return label
        case .activeTabs: return "Active Tabs"
        }
    }

    private var hint: String {
        switch item {
        case .tab: return "Switch to Tab"
        case .go(_, _, let isSearch): return isSearch ? "Search Google" : "Open"
        case .activeTabs(let count): return count == 1 ? "1 tab  ›" : "\(count) tabs  ›"
        }
    }
}
