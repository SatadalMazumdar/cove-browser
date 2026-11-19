import Foundation

// MARK: - File format, version 2

private struct SavedTab: Codable {
    var id: UUID
    var title: String
    var url: URL
    var state: Data?
}

private struct SavedFolder: Codable {
    var id: UUID
    var name: String
    var expanded: Bool
    var children: [SavedNode]
}

/// Exactly one of the two is set.
private struct SavedNode: Codable {
    var tab: SavedTab?
    var folder: SavedFolder?
}

private struct SavedProfile: Codable {
    var id: UUID
    var name: String
    var favorites: [SavedTab]
}

private struct SavedSpace: Codable {
    var id: UUID
    var name: String
    var icon: String
    var theme: SpaceTheme
    var profileID: UUID
    var pinned: [SavedNode]
    var today: [SavedTab]
    var selected: UUID?
    /// Optional so a file written before this field still reads, and so the v1 upgrade can omit it.
    var pinnedCollapsed: Bool? = nil
}

private struct SavedSession: Codable {
    var version = 2
    var spaceIndex: Int
    var sidebarVisible: Bool
    var profiles: [SavedProfile]
    var spaces: [SavedSpace]
    /// Optional so older files still read. Tab-sleeping delay in seconds, 0 means never.
    var idleSeconds: Double? = nil
    var blockingEnabled: Bool? = nil
}

// MARK: - Version 1, read only

/// Before profiles were split from spaces. Each space carried its own profile id and favorites.
private struct SavedSessionV1: Codable {
    struct Folder: Codable {
        var name: String
        var expanded: Bool
        var tabs: [SavedTab]
    }
    struct Space: Codable {
        var name: String
        var symbol: String
        var hue: Double
        var profileID: UUID
        var favorites: [SavedTab]
        var pinned: [SavedTab]
        var folders: [Folder]
        var today: [SavedTab]
        var selected: UUID?
    }
    var spaceIndex: Int
    var sidebarVisible: Bool
    var spaces: [Space]

    var upgraded: SavedSession {
        var profiles: [SavedProfile] = []
        var converted: [SavedSpace] = []
        for space in spaces {
            // Two old spaces never shared a profile, but guard against a hand-edited file.
            if !profiles.contains(where: { $0.id == space.profileID }) {
                profiles.append(SavedProfile(id: space.profileID, name: space.name, favorites: space.favorites))
            }
            let folders = space.folders.map { folder in
                SavedNode(folder: SavedFolder(id: UUID(), name: folder.name, expanded: folder.expanded,
                                              children: folder.tabs.map { SavedNode(tab: $0) }))
            }
            converted.append(SavedSpace(
                id: UUID(), name: space.name, icon: space.symbol, theme: SpaceTheme(hue: space.hue),
                profileID: space.profileID, pinned: space.pinned.map { SavedNode(tab: $0) } + folders,
                today: space.today, selected: space.selected
            ))
        }
        return SavedSession(spaceIndex: spaceIndex, sidebarVisible: sidebarVisible,
                            profiles: profiles, spaces: converted)
    }
}

// MARK: - Reading and writing

@MainActor
enum SessionFile {
    struct Loaded {
        var profiles: [Profile]
        var spaces: [Space]
        var spaceIndex: Int
        var sidebarVisible: Bool
        var idleSeconds: Double?
        var blockingEnabled: Bool?
    }

    /// ~/Library/Application Support/Cove/session.json, unless COVE_SESSION_FILE points elsewhere.
    static var url: URL {
        if let path = ProcessInfo.processInfo.environment["COVE_SESSION_FILE"] {
            return URL(fileURLWithPath: path)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Cove/session.json")
    }

    /// Returns nil on first launch, or when the file is unreadable. The caller then starts from the sample set.
    static func load() -> Loaded? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        if let session = try? decoder.decode(SavedSession.self, from: data), !session.spaces.isEmpty {
            return build(session)
        }
        if let old = try? decoder.decode(SavedSessionV1.self, from: data), !old.spaces.isEmpty {
            // The old file stays next to the new one, in case the upgrade got something wrong.
            let backup = url.deletingLastPathComponent().appendingPathComponent("session.v1.json")
            try? data.write(to: backup, options: .atomic)
            return build(old.upgraded)
        }
        return nil
    }

    private static func build(_ session: SavedSession) -> Loaded {
        func tab(_ record: SavedTab) -> BrowserTab {
            BrowserTab(title: record.title, url: record.url, id: record.id, state: record.state)
        }
        func node(_ record: SavedNode) -> Node? {
            if let saved = record.tab { return .tab(tab(saved)) }
            if let saved = record.folder {
                return .folder(TabFolder(name: saved.name, expanded: saved.expanded,
                                         children: saved.children.compactMap(node), id: saved.id))
            }
            return nil
        }

        var profiles = session.profiles.map {
            Profile(name: $0.name, id: $0.id, favorites: $0.favorites.map(tab))
        }
        let spaces = session.spaces.map { record -> Space in
            let profile: Profile
            if let found = profiles.first(where: { $0.id == record.profileID }) {
                profile = found
            } else {
                profile = Profile(name: record.name, id: record.profileID)
                profiles.append(profile)
            }
            let space = Space(name: record.name, icon: record.icon, theme: record.theme, profile: profile,
                              id: record.id, pinned: record.pinned.compactMap(node), today: record.today.map(tab),
                              pinnedCollapsed: record.pinnedCollapsed ?? false)
            space.selected = space.allTabs.first { $0.id == record.selected }
            return space
        }
        return Loaded(profiles: profiles, spaces: spaces,
                      spaceIndex: session.spaceIndex, sidebarVisible: session.sidebarVisible,
                      idleSeconds: session.idleSeconds, blockingEnabled: session.blockingEnabled)
    }

    static func save(_ store: BrowserStore) {
        func record(_ tab: BrowserTab) -> SavedTab {
            SavedTab(id: tab.id, title: tab.title, url: tab.url, state: tab.persistableState)
        }
        func record(_ node: Node) -> SavedNode {
            switch node {
            case .tab(let tab):
                return SavedNode(tab: record(tab))
            case .folder(let folder):
                return SavedNode(folder: SavedFolder(id: folder.id, name: folder.name, expanded: folder.expanded,
                                                     children: folder.children.map(record)))
            }
        }
        let session = SavedSession(
            spaceIndex: store.spaceIndex,
            sidebarVisible: store.sidebarVisible,
            profiles: store.profiles.map {
                SavedProfile(id: $0.id, name: $0.name, favorites: $0.favorites.map(record))
            },
            spaces: store.spaces.map { space in
                SavedSpace(id: space.id, name: space.name, icon: space.icon, theme: space.theme,
                           profileID: space.profile.id, pinned: space.pinned.map(record),
                           today: space.today.map(record), selected: space.selected?.id,
                           pinnedCollapsed: space.pinnedCollapsed)
            },
            idleSeconds: store.idleSeconds,
            blockingEnabled: store.blockingEnabled
        )
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(session).write(to: url, options: .atomic)
        } catch {
            NSLog("Cove could not save the session: \(error.localizedDescription)")
        }
    }
}
