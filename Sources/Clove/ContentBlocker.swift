import Foundation
import WebKit

/// Blocks ads and trackers with WebKit's own content rule list. The list is a curated set of
/// well-known ad and analytics hosts, blocked only as third-party requests so first-party sites
/// keep working. WebKit compiles the rules once; after that they cost nothing per page.
@MainActor
final class ContentBlocker {
    static let shared = ContentBlocker()

    private(set) var ruleList: WKContentRuleList?
    /// Flipped by the setting. When off, the compiled list is simply not attached.
    var enabled = true
    /// Called once the list has compiled, so the store can attach it to pages opened before then.
    var onReady: (() -> Void)?

    /// Hosts whose third-party requests are dropped. Domain names are facts; this is a hand-picked
    /// starter set, not a full filter list. History and a real list come later.
    private static let hosts = [
        "doubleclick.net", "googlesyndication.com", "googleadservices.com", "google-analytics.com",
        "googletagmanager.com", "googletagservices.com", "adservice.google.com", "analytics.google.com",
        "2mdn.net", "adnxs.com", "adsrvr.org", "rubiconproject.com", "pubmatic.com", "openx.net",
        "criteo.com", "criteo.net", "taboola.com", "outbrain.com", "scorecardresearch.com",
        "quantserve.com", "quantcount.com", "moatads.com", "adsafeprotected.com", "serving-sys.com",
        "bidswitch.net", "casalemedia.com", "sharethrough.com", "contextweb.com", "3lift.com",
        "amazon-adsystem.com", "advertising.com", "yieldmo.com", "smartadserver.com", "teads.tv",
        "facebook.net", "connect.facebook.net", "ads-twitter.com", "analytics.twitter.com",
        "bat.bing.com", "clarity.ms", "hotjar.com", "mouseflow.com", "fullstory.com", "mixpanel.com",
        "segment.com", "segment.io", "amplitude.com", "branch.io", "appsflyer.com", "adjust.com",
        "chartbeat.com", "newrelic.com", "nr-data.net", "sentry.io", "snowplowanalytics.com",
        "crazyegg.com", "optimizely.com", "demdex.net", "everesttech.net", "adobedtm.com",
        "omtrdc.net", "bluekai.com", "krxd.net", "agkn.com", "rlcdn.com", "crwdcntrl.net",
    ]

    /// The rule list, built with JSONSerialization so nothing has to be escaped by hand.
    private static func encodedRules() -> String {
        let rules: [[String: Any]] = hosts.map { host in
            let pattern = "https?://([^/]*\\.)?" + NSRegularExpression.escapedPattern(for: host)
            return ["trigger": ["url-filter": pattern, "load-type": ["third-party"]],
                    "action": ["type": "block"]]
        }
        let data = (try? JSONSerialization.data(withJSONObject: rules)) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    /// Exposes the encoded rules for the diagnostic check.
    static func sampleRules() -> String { encodedRules() }

    func prepare() {
        guard ruleList == nil, let store = WKContentRuleListStore.default() else { return }
        store.compileContentRuleList(forIdentifier: "clove-block-v1",
                                     encodedContentRuleList: Self.encodedRules()) { list, error in
            // The singleton lives for the whole app, so a strong capture here is fine.
            Task { @MainActor in
                if let error { NSLog("Clove content blocker failed to compile: \(error.localizedDescription)") }
                ContentBlocker.shared.ruleList = list
                ContentBlocker.shared.onReady?()
            }
        }
    }

    /// Attaches or detaches the list on one page. The store decides `on` per host.
    func apply(to webView: WKWebView, on: Bool) {
        let controller = webView.configuration.userContentController
        controller.removeAllContentRuleLists()
        if on, let ruleList { controller.add(ruleList) }
    }
}
