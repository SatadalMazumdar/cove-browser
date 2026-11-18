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
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    TextField("Search or Enter URL...", text: $store.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 19))
                        .foregroundStyle(.white)
                        .focused($focused)
                        .onSubmit { store.submit() }
                }
                .padding(.horizontal, 18)
                .frame(height: 58)

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
        }
    }

    private var title: String {
        switch item {
        case .tab(let tab): return tab.title
        case .go(_, let label, _): return label
        }
    }

    private var hint: String {
        switch item {
        case .tab: return "Switch to Tab"
        case .go(_, _, let isSearch): return isSearch ? "Search Google" : "Open"
        }
    }
}
