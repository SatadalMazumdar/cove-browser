import AppKit
import Combine
import WebKit

/// One file being downloaded or already done.
@MainActor
final class DownloadItem: ObservableObject, Identifiable {
    let id = UUID()
    @Published var filename: String
    @Published var fraction: Double = 0
    @Published var state: State = .running
    /// Where it landed, once a destination is chosen.
    @Published var fileURL: URL?

    enum State { case running, finished, failed }

    private var bag = Set<AnyCancellable>()

    init(filename: String) {
        self.filename = filename
    }

    /// Follows the download's progress object so the row's bar moves.
    func track(_ progress: Progress) {
        progress.publisher(for: \.fractionCompleted)
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.fraction = $0 }
            .store(in: &bag)
    }
}

/// Catches downloads from any page, saves them to the Downloads folder, and keeps a short list
/// for the sidebar. One manager is shared across every tab and profile.
@MainActor
final class DownloadManager: NSObject, ObservableObject, WKDownloadDelegate {
    @Published var items: [DownloadItem] = []
    /// Maps a live WKDownload to its row.
    private var rows: [ObjectIdentifier: DownloadItem] = [:]

    var hasActive: Bool { items.contains { $0.state == .running } }

    func register(_ download: WKDownload) {
        download.delegate = self
    }

    func clearFinished() {
        items.removeAll { $0.state != .running }
    }

    func reveal(_ item: DownloadItem) {
        guard let url = item.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: WKDownloadDelegate

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let name = suggestedFilename.isEmpty ? "download" : suggestedFilename
        let dest = Self.uniqueDownloadURL(for: name)
        let item = DownloadItem(filename: dest.lastPathComponent)
        item.fileURL = dest
        item.track(download.progress)
        rows[ObjectIdentifier(download)] = item
        items.insert(item, at: 0)
        completionHandler(dest)
    }

    func downloadDidFinish(_ download: WKDownload) {
        rows[ObjectIdentifier(download)]?.state = .finished
        rows[ObjectIdentifier(download)]?.fraction = 1
        rows.removeValue(forKey: ObjectIdentifier(download))
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        rows[ObjectIdentifier(download)]?.state = .failed
        rows.removeValue(forKey: ObjectIdentifier(download))
    }

    // MARK: Destination

    /// ~/Downloads/<name>, with " (1)", " (2)" and so on if something is already there.
    private static func uniqueDownloadURL(for name: String) -> URL {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = dir.appendingPathComponent(name)
        var n = 1
        while FileManager.default.fileExists(atPath: candidate.path) {
            let numbered = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            candidate = dir.appendingPathComponent(numbered)
            n += 1
        }
        return candidate
    }
}
