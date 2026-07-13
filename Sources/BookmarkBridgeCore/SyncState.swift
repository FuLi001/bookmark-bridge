import Foundation

public enum BridgeStatus: String, Codable, Sendable {
    case waitingForPermission
    case waitingForChrome
    case needsInitialization
    case ready
    case syncing
    case conflict
    case error
}

public struct SyncFolderConfiguration: Codable, Equatable, Sendable {
    public static let defaultSafariFolderID = "safari:favorites"
    public static let defaultChromeFolderID = "chrome:bookmark-bar"

    public var safariFolderID: String
    public var safariFolderPath: String
    public var chromeFolderID: String
    public var chromeFolderPath: String
    public var revision: Int

    public init(safariFolderID: String = Self.defaultSafariFolderID,
                safariFolderPath: String = "个人收藏",
                chromeFolderID: String = Self.defaultChromeFolderID,
                chromeFolderPath: String = "书签栏",
                revision: Int = 0) {
        self.safariFolderID = safariFolderID
        self.safariFolderPath = safariFolderPath
        self.chromeFolderID = chromeFolderID
        self.chromeFolderPath = chromeFolderPath
        self.revision = revision
    }
}

public struct PersistedSyncState: Codable, Sendable {
    public var automaticSyncEnabled: Bool
    public var baseline: BookmarkNode?
    public var commandRevision: Int
    public var folders: SyncFolderConfiguration

    public init(automaticSyncEnabled: Bool = false,
                baseline: BookmarkNode? = nil,
                commandRevision: Int = 0,
                folders: SyncFolderConfiguration = SyncFolderConfiguration()) {
        self.automaticSyncEnabled = automaticSyncEnabled
        self.baseline = baseline
        self.commandRevision = commandRevision
        self.folders = folders
    }

    private enum CodingKeys: String, CodingKey {
        case automaticSyncEnabled
        case baseline
        case commandRevision
        case folders
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        automaticSyncEnabled = try values.decodeIfPresent(Bool.self, forKey: .automaticSyncEnabled) ?? false
        baseline = try values.decodeIfPresent(BookmarkNode.self, forKey: .baseline)
        commandRevision = try values.decodeIfPresent(Int.self, forKey: .commandRevision) ?? 0
        folders = try values.decodeIfPresent(SyncFolderConfiguration.self, forKey: .folders)
            ?? SyncFolderConfiguration()
    }
}

public final class SyncStateStore {
    public let stateURL: URL

    public init(applicationSupport: URL? = nil) {
        let support = applicationSupport ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/BookmarkBridge")
        stateURL = support.appendingPathComponent("state.json")
    }

    public func load() -> PersistedSyncState {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(PersistedSyncState.self, from: data) else {
            return PersistedSyncState()
        }
        return state
    }

    public func save(_ state: PersistedSyncState) throws {
        try FileManager.default.createDirectory(
            at: stateURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: stateURL, options: .atomic)
    }
}
