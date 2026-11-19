import AppKit
import Combine
import SwiftUI
import WebKit

/// A small floating window with one page and a slim bar, like Arc's Little Arc. Opened for a link
/// you want a quick look at, on the current space's profile so you are already signed in. Promote
/// it into a real tab, or close it and it is gone.
@MainActor
final class MiniWindow: NSObject, ObservableObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    let window: NSWindow
    let webView: WKWebView
    private weak var store: BrowserStore?
    private let profile: Profile
    private var bag = Set<AnyCancellable>()

    @Published fileprivate var host = ""
    @Published fileprivate var title = ""
    @Published fileprivate var loading = false

    init(url: URL, profile: Profile, store: BrowserStore) {
        self.store = store
        self.profile = profile
        webView = WKWebView(frame: .zero, configuration: profile.makeConfiguration())
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 640),
                          styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        ContentBlocker.shared.apply(to: webView, on: store.blockingOn(for: url.host ?? ""))

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.level = .floating
        window.delegate = self
        window.center()

        let container = NSView()
        container.wantsLayer = true
        let bar = NSHostingView(rootView: MiniBar(mini: self,
                                                  promote: { [weak self] in self?.promote() },
                                                  close: { [weak self] in self?.window.close() }))
        bar.translatesAutoresizingMaskIntoConstraints = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(bar)
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: container.topAnchor),
            bar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 48),
            webView.topAnchor.constraint(equalTo: bar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        window.contentView = container

        webView.publisher(for: \.url).sink { [weak self] in self?.host = $0?.host ?? "" }.store(in: &bag)
        webView.publisher(for: \.title).sink { [weak self] in self?.title = $0 ?? "" }.store(in: &bag)
        webView.publisher(for: \.isLoading).sink { [weak self] in self?.loading = $0 }.store(in: &bag)

        webView.load(URLRequest(url: url))
        window.makeKeyAndOrderFront(nil)
    }

    /// Moves the current page into a real tab in the current space, then closes the mini window.
    private func promote() {
        if let url = webView.url { store?.newTab(url: url) }
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        webView.navigationDelegate = nil
        webView.stopLoading()
        store?.miniClosed(self)
    }

    // A link that opens a new window from inside the mini view just loads in place.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { webView.load(URLRequest(url: url)) }
        return nil
    }
}

private struct MiniBar: View {
    @ObservedObject var mini: MiniWindow
    let promote: () -> Void
    let close: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary).frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 1) {
                Text(mini.title.isEmpty ? mini.host : mini.title)
                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
                Text(mini.host).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if mini.loading { ProgressView().controlSize(.small) }
            Button(action: promote) {
                Label("Open as Tab", systemImage: "arrow.up.right.square")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            .help("Open this page as a tab in the current space")
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}
