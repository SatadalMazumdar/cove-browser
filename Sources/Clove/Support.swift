import Foundation

/// App storage locations, and a one-time copy from the old "Cove" name and bundle id so the
/// rename to Clove does not lose anyone's tabs, history or logins. It copies rather than moves,
/// so the old data stays in place as a backup.
enum Support {
    static let folder = "Clove"
    static let bundleID = "dev.clove.browser"
    private static let legacyFolder = "Cove"
    private static let legacyBundleID = "dev.prototype.cove"

    /// ~/Library/Application Support/Clove
    static var dir: URL {
        base(.applicationSupportDirectory).appendingPathComponent(folder)
    }

    static func file(_ name: String) -> URL { dir.appendingPathComponent(name) }

    /// ~/Library/Caches/Clove/<name>
    static func cache(_ name: String) -> URL {
        base(.cachesDirectory).appendingPathComponent(folder).appendingPathComponent(name)
    }

    private static func base(_ directory: FileManager.SearchPathDirectory) -> URL {
        FileManager.default.urls(for: directory, in: .userDomainMask)[0]
    }

    /// The iCloud Drive folder for Clove, or nil when iCloud Drive is off. A plain path that
    /// iCloud syncs on its own, which is as much cross-machine sync as an unsigned build can do.
    static var iCloudDir: URL? {
        let cloudDocs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        guard FileManager.default.fileExists(atPath: cloudDocs.path) else { return nil }
        return cloudDocs.appendingPathComponent(folder)
    }

    /// Runs once, before anything reads storage. Carries over app data, and the WebKit and cookie
    /// stores (keyed by bundle id) so sites stay signed in across the bundle-id change.
    static func migrateFromLegacy() {
        let fm = FileManager.default
        func copyOnce(_ old: URL, _ new: URL) {
            guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: new.path) else { return }
            try? fm.createDirectory(at: new.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.copyItem(at: old, to: new)
        }

        let support = base(.applicationSupportDirectory)
        copyOnce(support.appendingPathComponent(legacyFolder), support.appendingPathComponent(folder))

        let library = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        for sub in ["WebKit", "HTTPStorages"] {
            let dir = library.appendingPathComponent(sub)
            copyOnce(dir.appendingPathComponent(legacyBundleID), dir.appendingPathComponent(bundleID))
            copyOnce(dir.appendingPathComponent(legacyBundleID + ".binarycookies"),
                     dir.appendingPathComponent(bundleID + ".binarycookies"))
        }
    }
}
