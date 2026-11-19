import AppKit
import Security
import WebKit

/// Clove's own password manager. Safari's autofill is not open to a third-party web view, and the
/// Apple Passwords app has no read API, so this keeps its own credentials in the login keychain.
/// A script in every page offers to save a login on submit and fills a saved one on return.
@MainActor
final class PasswordManager: NSObject, WKScriptMessageHandler {
    static let shared = PasswordManager()

    /// Off disables both saving and filling. Set from Settings.
    var enabled = true

    /// Injected into every page. Reports a submitted login, and asks for a saved one on load.
    static let script = """
    (function () {
      if (window.__clovePW) return; window.__clovePW = true;
      function user(form) {
        return form.querySelector('input[autocomplete="username"]')
            || form.querySelector('input[type="email"]')
            || form.querySelector('input[type="text"]');
      }
      document.addEventListener('submit', function (e) {
        try {
          var pw = e.target.querySelector('input[type="password"]');
          if (!pw || !pw.value) return;
          var u = user(e.target);
          webkit.messageHandlers.clovePasswords.postMessage(
            { action: 'save', host: location.host, username: u ? u.value : '', password: pw.value });
        } catch (err) {}
      }, true);
      webkit.messageHandlers.clovePasswords.postMessage({ action: 'fill', host: location.host });
    })();
    """

    // MARK: Message handler

    nonisolated func userContentController(_ controller: WKUserContentController,
                                           didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let action = body["action"] as? String,
              let host = body["host"] as? String else { return }
        let webView = message.webView
        Task { @MainActor in
            guard self.enabled, !host.isEmpty else { return }
            switch action {
            case "save":
                let user = body["username"] as? String ?? ""
                let pass = body["password"] as? String ?? ""
                self.offerToSave(host: host, user: user, pass: pass)
            case "fill":
                if let cred = self.credentials(for: host).first, let webView {
                    self.fill(webView, user: cred.account, pass: cred.password)
                }
            default: break
            }
        }
    }

    // MARK: Save flow

    private func offerToSave(host: String, user: String, pass: String) {
        guard !pass.isEmpty else { return }
        // Already saved with the same value: do nothing.
        if credentials(for: host).contains(where: { $0.account == user && $0.password == pass }) { return }
        let alert = NSAlert()
        alert.messageText = "Save password for \(host)?"
        alert.informativeText = user.isEmpty ? "Clove can fill it next time." : "\(user). Clove can fill it next time."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn {
            save(host: host, account: user, password: pass)
        }
    }

    private func fill(_ webView: WKWebView, user: String, pass: String) {
        guard let passJSON = encode(pass), let userJSON = encode(user) else { return }
        let js = """
        (function () {
          var pw = document.querySelector('input[type="password"]');
          if (!pw) return;
          var form = pw.form;
          if (\(userJSON) && form) {
            var u = form.querySelector('input[autocomplete="username"], input[type="email"], input[type="text"]');
            if (u) u.value = \(userJSON);
          }
          pw.value = \(passJSON);
        })();
        """
        webView.evaluateJavaScript(js)
    }

    private func encode(_ value: String) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let array = String(data: data, encoding: .utf8) else { return nil }
        return String(array.dropFirst().dropLast())  // the JSON string element, quotes kept
    }

    // MARK: Keychain

    struct Credential { var account: String; var password: String }

    private func base(_ host: String) -> [String: Any] {
        [kSecClass as String: kSecClassInternetPassword,
         kSecAttrServer as String: host,
         kSecAttrService as String: "Clove",
         // Use the file-based login keychain, the same one across add and read.
         kSecUseDataProtectionKeychain as String: false]
    }

    func save(host: String, account: String, password: String) {
        guard let data = password.data(using: .utf8) else { return }
        var query = base(host)
        query[kSecAttrAccount as String] = account
        SecItemDelete(query as CFDictionary)
        query[kSecValueData as String] = data
        query[kSecAttrLabel as String] = "Clove — \(host)"
        SecItemAdd(query as CFDictionary, nil)
    }

    func credentials(for host: String) -> [Credential] {
        // One item with its data. Returning data for many items at once is not reliable here.
        var query = base(host)
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let item = result as? [String: Any],
              let account = item[kSecAttrAccount as String] as? String,
              let data = item[kSecValueData as String] as? Data,
              let password = String(data: data, encoding: .utf8) else { return [] }
        return [Credential(account: account, password: password)]
    }

    /// Every saved login across all sites, for the Settings list. Sorted by site.
    func all() -> [(host: String, account: String)] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrService as String: "Clove",
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecUseDataProtectionKeychain as String: false,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let host = item[kSecAttrServer as String] as? String else { return nil }
            return (host, item[kSecAttrAccount as String] as? String ?? "")
        }.sorted { $0.host < $1.host }
    }

    var count: Int { all().count }

    func forgetAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrService as String: "Clove",
            kSecUseDataProtectionKeychain as String: false,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
