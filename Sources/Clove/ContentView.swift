import SwiftUI
import WebKit

struct ContentView: View {
    @ObservedObject var store: BrowserStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        SpaceScene(store: store, space: store.space)
            .environment(\.theme, blendedTheme)
            .ignoresSafeArea()
    }
}

extension ContentView {
    /// Mid-swipe, the window tint sits between the two spaces' colours.
    var blendedTheme: Theme {
        let last = Double(store.spaces.count - 1)
        let position = min(max(store.pagePosition, 0), last)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, store.spaces.count - 1)
        return Theme.between(store.spaces[lower].theme, store.spaces[upper].theme,
                             fraction: position - Double(lower), systemDark: colorScheme == .dark)
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
                // Full screen runs the page edge to edge, no gutter and no rounded corners.
                // A window keeps the gutter, with the leading side flush against the sidebar.
                webCard
                    .padding(.vertical, store.fullScreen ? 0 : Metrics.gutter)
                    .padding(.trailing, store.fullScreen ? 0 : Metrics.gutter)
                    .padding(.leading, store.fullScreen || store.sidebarVisible ? 0 : Metrics.gutter)
            }

            if !store.sidebarVisible { floatingSidebar }

            if store.commandBar != nil {
                CommandBar(store: store)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            if let panel = store.panel {
                PanelHost(store: store, panel: panel)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.sidebarVisible)
        .animation(.easeOut(duration: 0.2), value: store.fullScreen)
        .animation(.easeOut(duration: 0.12), value: store.commandBar != nil)
        .animation(.easeOut(duration: 0.12), value: store.panel != nil)
        .animation(.easeOut(duration: 0.18), value: store.peeking)
        .onChange(of: store.sidebarVisible) { _, _ in store.peeking = false }
    }

    /// No rounded corners when the page runs edge to edge in full screen.
    private var cardRadius: CGFloat { store.fullScreen ? 0 : Metrics.cardRadius }

    private var webCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                .fill(theme.card)
                .shadow(color: store.fullScreen ? .clear : .black.opacity(0.22), radius: 6, y: 1)
            if let split = space.splitTab, let left = space.selected?.webView, let right = split.webView {
                HStack(spacing: 6) {
                    pane(left)
                    pane(right).overlay(alignment: .topTrailing) { splitCloseButton }
                }
                .id(space.id)
            } else if let webView = space.selected?.webView {
                pane(webView).id(space.id).transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            if store.finding {
                FindBar(store: store)
                    .padding(14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.15), value: store.finding)
        .animation(.easeOut(duration: 0.18), value: space.splitTab != nil)
    }

    private func pane(_ webView: WKWebView) -> some View {
        WebContainer(webView: webView, radius: cardRadius)
            .clipShape(RoundedRectangle(cornerRadius: cardRadius, style: .continuous))
    }

    private var splitCloseButton: some View {
        Button { store.closeSplit() } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.white, .black.opacity(0.4))
                .padding(8)
        }
        .buttonStyle(.plain)
        .help("Close split")
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
                // Explicit shadow cast onto the page. A SwiftUI .shadow would be hidden under the
                // web view's layer, so it is drawn as a real gradient that sits above the page.
                LinearGradient(colors: [.black.opacity(0.32), .black.opacity(0.12), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 26)
                    .frame(maxHeight: .infinity)
                    .padding(.leading, Metrics.sidebarWidth + 6)
                    .allowsHitTesting(false)
                    .transition(.opacity)

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
                    .overlay {
                        // A hairline edge so the panel reads against a bright page.
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                    }
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
    var radius: CGFloat = Metrics.cardRadius

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerRadius = radius
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        container.layer?.cornerRadius = radius
        guard container.subviews.first !== webView else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        webView.frame = container.bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)
    }
}
