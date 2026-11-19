import Foundation
import Sparkle

/// Sparkle auto-update. The feed URL and the EdDSA public key live in Info.plist, written by build.sh.
@MainActor
enum Updater {
    private static var controller: SPUStandardUpdaterController?

    /// Starts the background update check. Does nothing when run outside the app bundle,
    /// such as a bare `swift run`, where there is no feed URL.
    static func start() {
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    static var available: Bool { controller != nil }

    static func check() { controller?.checkForUpdates(nil) }
}
