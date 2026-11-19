import Foundation
import WebKit

/// One user script: custom JavaScript that runs on sites matching a pattern. This is Clove's
/// stand-in for extensions. Full Safari web extensions need an Xcode app-extension target and
/// signing, which the Command Line Tools build cannot produce; userscripts cover the common case.
struct Userscript: Codable, Identifiable {
    var id = UUID()
    var name: String
    /// A host glob: "*" for all sites, "example.com", or "*.example.com".
    var match: String
    var code: String
    var enabled: Bool = true
}

@MainActor
final class UserscriptStore: ObservableObject {
    static let shared = UserscriptStore()

    @Published var scripts: [Userscript] = []
    /// Set by the browser store so edits re-inject into open pages.
    var onChange: (() -> Void)?

    private var fileURL: URL { Support.file("userscripts.json") }

    init() { load() }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([Userscript].self, from: data) else { return }
        scripts = list
    }

    func save() {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(scripts).write(to: fileURL, options: .atomic)
        onChange?()
    }

    func add() {
        scripts.append(Userscript(name: "New Script", match: "*", code: "// Runs on matching pages\n"))
        save()
    }

    func delete(_ script: Userscript) {
        scripts.removeAll { $0.id == script.id }
        save()
    }

    /// The host test for a glob, as a JS boolean expression over the variable `h`.
    private func matchExpression(_ pattern: String) -> String {
        let p = pattern.trimmingCharacters(in: .whitespaces)
        if p.isEmpty || p == "*" { return "true" }
        let host = p.hasPrefix("*.") ? String(p.dropFirst(2)) : p
        guard let data = try? JSONSerialization.data(withJSONObject: [host]),
              let json = String(data: data, encoding: .utf8) else { return "false" }
        let quoted = String(json.dropFirst().dropLast())  // the JSON-escaped host, quotes kept
        return "(h === \(quoted) || h.endsWith('.' + \(quoted)))"
    }

    /// Wraps each enabled script in a host check so it only runs where it should.
    func wkUserScripts() -> [WKUserScript] {
        scripts.filter(\.enabled).map { script in
            let source = """
            (function () {
              var h = location.host;
              if (!\(matchExpression(script.match))) return;
              try { \(script.code)
              } catch (e) { console.error('Clove userscript error', e); }
            })();
            """
            return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        }
    }
}

/// Fills a content controller with everything Clove injects: the password helper and the userscripts.
/// Kept in one place so re-injecting after an edit does not drop the password script.
@MainActor
enum WebScripts {
    static func populate(_ controller: WKUserContentController) {
        controller.removeAllUserScripts()
        controller.addUserScript(
            WKUserScript(source: PasswordManager.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        for script in UserscriptStore.shared.wkUserScripts() { controller.addUserScript(script) }
    }
}
