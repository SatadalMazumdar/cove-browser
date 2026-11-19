import AppKit
import CryptoKit
import Foundation

/// Reads Arc's sidebar from disk: spaces, their themes and icons, favorites, pinned tabs, folders and open tabs.
/// Arc keeps all of it as plain JSON. Cookies and saved passwords are encrypted with a key in the
/// keychain, so they are left alone.
struct ArcImport {
    struct Tab {
        var title: String
        var url: URL
    }

    indirect enum Item {
        case tab(Tab)
        case folder(name: String, children: [Item])

        var tabCount: Int {
            switch self {
            case .tab: return 1
            case .folder(_, let children): return children.reduce(0) { $0 + $1.tabCount }
            }
        }

        var folderCount: Int {
            switch self {
            case .tab: return 0
            case .folder(_, let children): return 1 + children.reduce(0) { $0 + $1.folderCount }
            }
        }
    }

    struct ProfileRecord {
        /// "Default", "Profile 1" and so on. Arc's name for the profile's folder.
        var key: String
        var name: String
        var favorites: [Tab]
    }

    struct SpaceRecord {
        var name: String
        var icon: String
        var theme: SpaceTheme
        var profileKey: String
        var pinned: [Item]
        var today: [Tab]

        var pinnedTabCount: Int { pinned.reduce(0) { $0 + $1.tabCount } }
        var folderCount: Int { pinned.reduce(0) { $0 + $1.folderCount } }
    }

    enum Failure: LocalizedError {
        case notFound
        case unreadable

        var errorDescription: String? {
            switch self {
            case .notFound: return "No Arc data was found on this Mac."
            case .unreadable: return "Arc's sidebar file is in a format this version cannot read."
            }
        }
    }

    var profiles: [ProfileRecord] = []
    var spaces: [SpaceRecord] = []

    static var arcFolder: URL {
        if let path = ProcessInfo.processInfo.environment["COVE_ARC_FOLDER"] {
            return URL(fileURLWithPath: path)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Arc")
    }

    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: arcFolder.appendingPathComponent("StorableSidebar.json").path)
    }

    /// A profile imported twice lands on the same data store, so a second import keeps the logins.
    static func profileID(for key: String) -> UUID {
        let digest = Array(SHA256.hash(data: Data(("arc-profile:" + key).utf8)))
        return UUID(uuid: (digest[0], digest[1], digest[2], digest[3], digest[4], digest[5], digest[6], digest[7],
                           digest[8], digest[9], digest[10], digest[11], digest[12], digest[13], digest[14], digest[15]))
    }

    // MARK: Reading

    private typealias JSON = [String: Any]

    static func read(from folder: URL = arcFolder) throws -> ArcImport {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("StorableSidebar.json")) else {
            throw Failure.notFound
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? JSON,
              let containers = (root["sidebar"] as? JSON)?["containers"] as? [Any],
              // Arc also keeps a small container for Little Arc windows. The sidebar is the one with the most spaces.
              let container = containers.compactMap({ $0 as? JSON })
                  .max(by: { ($0["spaces"] as? [Any] ?? []).count < ($1["spaces"] as? [Any] ?? []).count }),
              container["spaces"] != nil
        else { throw Failure.unreadable }

        // Arc writes both lists as id, record, id, record. Only the records matter here.
        let rawItems = (container["items"] as? [Any] ?? []).compactMap { $0 as? JSON }
        var items: [String: JSON] = [:]
        for item in rawItems {
            if let id = item["id"] as? String { items[id] = item }
        }
        var rawSpaces = (container["spaces"] as? [Any] ?? []).compactMap { $0 as? JSON }

        // The order shown in Arc's sidebar is kept apart from the records.
        let sync = ((root["sidebarSyncState"] as? JSON)?["container"] as? JSON)?["value"] as? JSON
        if let order = sync?["orderedSpaceIDs"] as? [String] {
            func rank(_ space: JSON) -> Int { order.firstIndex(of: space["id"] as? String ?? "") ?? Int.max }
            rawSpaces = rawSpaces.enumerated()
                .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
                .map(\.element)
        }

        func tab(_ item: JSON) -> Tab? {
            guard let saved = (item["data"] as? JSON)?["tab"] as? JSON,
                  let address = saved["savedURL"] as? String, let url = URL(string: address),
                  let scheme = url.scheme?.lowercased(), ["http", "https", "file"].contains(scheme)
            else { return nil }
            let title = (item["title"] as? String) ?? (saved["savedTitle"] as? String) ?? url.host ?? address
            return Tab(title: title.isEmpty ? (url.host ?? address) : title, url: url)
        }

        func children(of id: String?) -> [JSON] {
            guard let id, let ids = items[id]?["childrenIds"] as? [String] else { return [] }
            return ids.compactMap { items[$0] }
        }

        /// Arc can nest folders and put two tabs in a split view. A split view comes over as its tabs.
        func tree(_ item: JSON) -> [Item] {
            let data = item["data"] as? JSON ?? [:]
            if data["tab"] != nil { return tab(item).map { [.tab($0)] } ?? [] }
            let inner = children(of: item["id"] as? String).flatMap(tree)
            if data["list"] != nil {
                return [.folder(name: item["title"] as? String ?? "Folder", children: inner)]
            }
            return inner
        }

        func flat(_ list: [Item]) -> [Tab] {
            list.flatMap { item -> [Tab] in
                switch item {
                case .tab(let tab): return [tab]
                case .folder(_, let children): return flat(children)
                }
            }
        }

        func profileKey(_ value: Any?) -> String {
            let custom = ((value as? JSON)?["custom"] as? JSON)?["_0"] as? JSON
            return custom?["directoryBasename"] as? String ?? "Default"
        }

        // Chromium's own record of what the user named each profile.
        var names: [String: String] = [:]
        if let state = try? Data(contentsOf: folder.appendingPathComponent("User Data/Local State")),
           let json = try? JSONSerialization.jsonObject(with: state) as? JSON,
           let cache = (json["profile"] as? JSON)?["info_cache"] as? [String: JSON] {
            for (key, info) in cache { names[key] = info["name"] as? String }
        }

        // Favorites sit in one container per profile.
        var favorites: [String: [Tab]] = [:]
        for item in rawItems {
            let kind = ((item["data"] as? JSON)?["itemContainer"] as? JSON)?["containerType"] as? JSON
            guard let top = kind?["topApps"] as? JSON else { continue }
            favorites[profileKey(top["_0"]), default: []] += flat(children(of: item["id"] as? String).flatMap(tree))
        }

        var result = ArcImport()
        for space in rawSpaces {
            // containerIDs reads "pinned", id, "unpinned", id.
            var containerFor: [String: String] = [:]
            let pairs = space["containerIDs"] as? [String] ?? []
            for index in stride(from: 0, to: pairs.count - 1, by: 2) { containerFor[pairs[index]] = pairs[index + 1] }

            let key = profileKey(space["profile"])
            let info = space["customInfo"] as? JSON
            let record = SpaceRecord(
                name: space["title"] as? String ?? "Space",
                icon: icon(from: info?["iconType"]),
                theme: theme(from: info?["windowTheme"] as? JSON),
                profileKey: key,
                pinned: children(of: containerFor["pinned"]).flatMap(tree),
                today: flat(children(of: containerFor["unpinned"]).flatMap(tree))
            )
            result.spaces.append(record)
            if !result.profiles.contains(where: { $0.key == key }) {
                result.profiles.append(ProfileRecord(key: key, name: names[key] ?? key, favorites: favorites[key] ?? []))
            }
        }
        guard !result.spaces.isEmpty else { throw Failure.unreadable }
        return result
    }

    // MARK: Icons and colours

    /// Arc's built-in icon names mapped to clean SF Symbols. Cove uses no emoji.
    private static let iconNames: [String: String] = [
        "planet": "globe", "folder": "folder.fill", "medical": "cross.case.fill", "bulb": "lightbulb.fill",
        "skull": "flame.fill", "star": "star.fill", "heart": "heart.fill", "home": "house.fill",
        "book": "book.fill", "briefcase": "briefcase.fill", "code": "terminal.fill", "game": "gamecontroller.fill",
        "music": "music.note", "leaf": "leaf.fill", "flame": "flame.fill", "moon": "moon.fill",
        "sunny": "sun.max.fill", "cloud": "cloud.fill", "airplane": "airplane", "cart": "cart.fill",
        "cafe": "cup.and.saucer.fill", "pizza": "fork.knife", "school": "graduationcap.fill", "brush": "paintbrush.fill",
        "camera": "camera.fill", "bookmark": "bookmark.fill", "flask": "flask.fill", "football": "sportscourt.fill",
        "paw": "pawprint.fill", "rocket": "sparkles", "terminal": "keyboard.fill", "wallet": "creditcard.fill",
        "gift": "gift.fill", "flower": "camera.macro", "fitness": "figure.strengthtraining.traditional", "film": "film.fill",
        "diamond": "diamond.fill", "earth": "globe", "mail": "envelope.fill", "people": "person.2.fill",
        "person": "person.fill", "flash": "bolt.fill",
    ]

    /// Arc also lets a space use an emoji. Those have no clean symbol, so they take the fallback.
    private static func icon(from value: Any?) -> String {
        guard let kind = value as? JSON, let name = kind["icon"] as? String else { return "globe" }
        return iconNames[name] ?? "globe"
    }

    /// Arc stores a full palette per space. Cove needs a hue and how strong the tint is,
    /// so this reads them off the palette's most saturated colour.
    private static func theme(from value: JSON?) -> SpaceTheme {
        guard let value else { return SpaceTheme() }
        let modes = (value["semanticColorPalette"] as? JSON)?["appearanceBased"] as? JSON
        let dark = modes?["dark"] as? JSON
        let light = modes?["light"] as? JSON
        let candidates: [Any?] = [
            (value["primaryColorPalette"] as? JSON)?["midTone"],
            dark?["minContrastColor"], light?["maxContrastColor"], light?["foregroundPrimary"],
        ]
        var theme = SpaceTheme()
        if dark != nil, light == nil { theme.mode = .dark }
        if light != nil, dark == nil { theme.mode = .light }
        // Arc tints its window harder than the palette's middle tone suggests, so the strongest colour wins.
        var best = -1.0
        for case let colour as JSON in candidates {
            guard let red = colour["red"] as? Double, let green = colour["green"] as? Double,
                  let blue = colour["blue"] as? Double else { continue }
            let converted = NSColor(srgbRed: red, green: green, blue: blue, alpha: 1)
            let saturation = Double(converted.saturationComponent)
            guard saturation > best else { continue }
            best = saturation
            theme.hue = Double(converted.hueComponent)
            theme.intensity = min(1, saturation * 1.1)
        }
        return theme
    }
}

// MARK: - Applying an import

struct ArcImportOptions {
    /// Which of the plan's spaces to bring over, by position.
    var chosen: Set<Int>
    var includeToday = false
    var replaceExisting = false
}

extension BrowserStore {
    func apply(_ plan: ArcImport, options: ArcImportOptions) {
        func tab(_ record: ArcImport.Tab) -> BrowserTab {
            BrowserTab(title: record.title, url: record.url)
        }
        func node(_ item: ArcImport.Item) -> Node {
            switch item {
            case .tab(let record): return .tab(tab(record))
            case .folder(let name, let children): return .folder(TabFolder(name: name, children: children.map(node)))
            }
        }

        var imported: [Space] = []
        for (index, record) in plan.spaces.enumerated() where options.chosen.contains(index) {
            let id = ArcImport.profileID(for: record.profileKey)
            let profile: Profile
            if let existing = profiles.first(where: { $0.id == id }) {
                profile = existing
            } else {
                let source = plan.profiles.first { $0.key == record.profileKey }
                profile = Profile(name: source?.name ?? record.profileKey, id: id,
                                  favorites: (source?.favorites ?? []).map(tab))
                profiles.append(profile)
            }
            imported.append(Space(name: record.name, icon: record.icon, theme: record.theme, profile: profile,
                                  pinned: record.pinned.map(node),
                                  today: options.includeToday ? record.today.map(tab) : []))
        }
        guard !imported.isEmpty else { return }

        if options.replaceExisting {
            spaces.forEach { space in space.ownTabs.forEach { $0.unload() } }
            spaces = imported
            spaceIndex = 0
        } else {
            spaceIndex = spaces.count
            spaces += imported
        }
        pagePosition = Double(spaceIndex)
        // A profile left with no space keeps its data, but its pages have nowhere to show.
        for profile in profiles where spaces(using: profile).isEmpty {
            profile.favorites.forEach { $0.unload() }
        }
        structureChanged()
        if space.selected == nil, let first = space.today.first ?? space.ownTabs.first ?? space.profile.favorites.first {
            select(first)
        }
    }
}
