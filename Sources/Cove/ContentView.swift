import SwiftUI
import WebKit

struct ContentView: View {
    @ObservedObject var store: BrowserStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SpaceScene(store: store, space: store.space)
            .environment(\.theme, Theme(hue: blendedHue, dark: colorScheme == .dark))
            .ignoresSafeArea()
    }
}

extension ContentView {
    /// Mid-swipe, the window tint sits between the two spaces' colours.
    var blendedHue: Double {
        let last = Double(store.spaces.count - 1)
        let position = min(max(store.pagePosition, 0), last)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, store.spaces.count - 1)
        let fraction = position - Double(lower)
        return store.spaces[lower].hue + (store.spaces[upper].hue - store.spaces[lower].hue) * fraction
    }
}

/// One space filling the window: tinted background, sidebar, and the web card.
private struct SpaceScene: View {
    @ObservedObject var store: BrowserStore
    @ObservedObject var space: Space
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [theme.backgroundTop, theme.backgroundBottom],
                           startPoint: .topLeading, endPoint: .bottomTrailing)

            HStack(spacing: 0) {
                if store.sidebarVisible {
                    SidebarView(store: store)
                        .frame(width: Metrics.sidebarWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }
                webCard
                    .padding(.vertical, Metrics.gutter)
                    .padding(.trailing, Metrics.gutter)
                    .padding(.leading, store.sidebarVisible ? 0 : Metrics.gutter)
            }

            if !store.sidebarVisible { floatingSidebar }

            if store.commandBar != nil {
                CommandBar(store: store)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.sidebarVisible)
        .animation(.easeOut(duration: 0.12), value: store.commandBar != nil)
        .animation(.easeOut(duration: 0.18), value: store.peeking)
        .onChange(of: store.sidebarVisible) { _, _ in store.peeking = false }
    }

    private var webCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
                .fill(theme.card)
                .shadow(color: .black.opacity(0.22), radius: 6, y: 1)
            if let webView = space.selected?.webView {
                WebContainer(webView: webView)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous))
                    .id(space.id)
                    .transition(.opacity)
            }
        }
    }

    /// With the sidebar hidden, touching the left edge slides it in over the page.
    private var floatingSidebar: some View {
        ZStack(alignment: .leading) {
            Color.clear
                .frame(width: 6)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .onHover { if $0 { store.peeking = true } }

            if store.peeking {
                SidebarView(store: store, floating: true)
                    .padding(.top, 8)
                    .frame(width: Metrics.sidebarWidth)
                    .frame(maxHeight: .infinity)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(LinearGradient(colors: [theme.backgroundTop, theme.backgroundBottom],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.35), radius: 18, x: 4)
                    .padding(6)
                    .onHover { if !$0 { store.peeking = false } }
                    .transition(.move(edge: .leading))
            }
        }
    }
}

/// Hosts whichever tab's web view is current. Tabs keep their own web views alive,
/// so switching swaps the subview and never reloads the page.
private struct WebContainer: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = Metrics.cardRadius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard container.subviews.first !== webView else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
    }
}
