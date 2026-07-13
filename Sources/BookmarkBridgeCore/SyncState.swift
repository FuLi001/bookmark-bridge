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

public struct PersistedSyncState: Codable, Sendable {
    public var automaticSyncEnabled: Bool
    public var baseline: BookmarkNode?
    public var commandRevision: Int

    public init(automaticSyncEnabled: Bool = false,
                baseline: BookmarkNode? = nil,
                commandRevision: Int = 0) {
        self.automaticSyncEnabled = automaticSyncEnabled
        self.baseline = baseline
        self.commandRevision = commandRevision
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
