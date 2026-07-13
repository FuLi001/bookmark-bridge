import Foundation

public enum SafariStoreError: LocalizedError {
    case invalidPropertyList
    case favoritesFolderNotFound
    case favoritesChildrenMissing

    public var errorDescription: String? {
        switch self {
        case .invalidPropertyList:
            return "Safari 书签文件格式无法识别"
        case .favoritesFolderNotFound:
            return "找不到 Safari 的个人收藏目录"
        case .favoritesChildrenMissing:
            return "Safari 个人收藏目录缺少子项"
        }
    }
}

public struct SafariFileFingerprint: Equatable {
    public let modificationDate: Date?
    public let fileSize: UInt64
    public let systemFileNumber: UInt64

    public init(modificationDate: Date?, fileSize: UInt64, systemFileNumber: UInt64) {
        self.modificationDate = modificationDate
        self.fileSize = fileSize
        self.systemFileNumber = systemFileNumber
    }
}

public final class SafariBookmarkStore {
    public let bookmarksURL: URL
    public let backupDirectory: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
                applicationSupport: URL? = nil) {
        bookmarksURL = homeDirectory
            .appendingPathComponent("Library/Safari/Bookmarks.plist")
        let support = applicationSupport ?? homeDirectory
            .appendingPathComponent("Library/Application Support/BookmarkBridge")
        backupDirectory = support.appendingPathComponent("Backups")
    }

    public func readFavorites() throws -> BookmarkNode {
        let data = try Data(contentsOf: bookmarksURL)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let root = plist as? [String: Any],
              let children = root["Children"] as? [[String: Any]] else {
            throw SafariStoreError.invalidPropertyList
        }
        guard let favorites = children.first(where: Self.isFavoritesFolder) else {
            throw SafariStoreError.favoritesFolderNotFound
        }
        guard let favoriteChildren = favorites["Children"] as? [[String: Any]] else {
            throw SafariStoreError.favoritesChildrenMissing
        }
        return .folder("root", children: favoriteChildren.compactMap(Self.decodeNode))
    }

    @discardableResult
    public func replaceFavorites(with tree: BookmarkNode) throws -> URL {
        let originalData = try Data(contentsOf: bookmarksURL)
        let plist = try PropertyListSerialization.propertyList(from: originalData, options: [], format: nil)
        guard var root = plist as? [String: Any],
              var rootChildren = root["Children"] as? [[String: Any]],
              let favoritesIndex = rootChildren.firstIndex(where: Self.isFavoritesFolder) else {
            throw SafariStoreError.favoritesFolderNotFound
        }

        var favorites = rootChildren[favoritesIndex]
        let existing = favorites["Children"] as? [[String: Any]] ?? []
        favorites["Children"] = Self.encodeChildren(tree.children, preserving: existing)
        rootChildren[favoritesIndex] = favorites
        root["Children"] = rootChildren

        try FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let backup = backupDirectory.appendingPathComponent("Safari-Bookmarks-\(formatter.string(from: Date())).plist")
        try originalData.write(to: backup, options: .atomic)

        let newData = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        try newData.write(to: bookmarksURL, options: .atomic)
        return backup
    }

    public func fingerprint() throws -> SafariFileFingerprint {
        let attributes = try FileManager.default.attributesOfItem(atPath: bookmarksURL.path)
        return SafariFileFingerprint(
            modificationDate: attributes[.modificationDate] as? Date,
            fileSize: (attributes[.size] as? NSNumber)?.uint64Value ?? 0,
            systemFileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        )
    }

    private static func isFavoritesFolder(_ dictionary: [String: Any]) -> Bool {
        let title = dictionary["Title"] as? String ?? ""
        let identifiers = [
            title,
            dictionary["WebBookmarkIdentifier"] as? String ?? "",
            dictionary["Identifier"] as? String ?? "",
        ].map { $0.lowercased() }
        return identifiers.contains(where: {
            $0 == "bookmarksbar" || $0 == "favorites" || $0 == "个人收藏" ||
            $0.contains("bookmarksbar") || $0.contains("favorites")
        })
    }

    private static func decodeNode(_ dictionary: [String: Any]) -> BookmarkNode? {
        let type = dictionary["WebBookmarkType"] as? String ?? ""
        if type == "WebBookmarkTypeList" || dictionary["Children"] != nil {
            let children = (dictionary["Children"] as? [[String: Any]] ?? []).compactMap(decodeNode)
            return .folder(dictionary["Title"] as? String ?? "未命名文件夹", children: children)
        }

        guard let url = dictionary["URLString"] as? String else { return nil }
        let uri = dictionary["URIDictionary"] as? [String: Any]
        let title = uri?["title"] as? String
            ?? dictionary["Title"] as? String
            ?? url
        return .bookmark(title, url: url)
    }

    private static func encodeChildren(_ nodes: [BookmarkNode], preserving existing: [[String: Any]]) -> [[String: Any]] {
        var unused = existing
        return nodes.map { node in
            let matchIndex = unused.firstIndex(where: { existingNode in
                if node.kind == .folder {
                    return (existingNode["Children"] != nil || existingNode["WebBookmarkType"] as? String == "WebBookmarkTypeList")
                        && existingNode["Title"] as? String == node.title
                }
                return existingNode["URLString"] as? String == node.url
            })
            let matched = matchIndex.map { unused.remove(at: $0) }
            return encodeNode(node, preserving: matched)
        }
    }

    private static func encodeNode(_ node: BookmarkNode, preserving existing: [String: Any]?) -> [String: Any] {
        var dictionary = existing ?? [:]
        dictionary["WebBookmarkUUID"] = dictionary["WebBookmarkUUID"]
            ?? dictionary["UUID"]
            ?? UUID().uuidString
        dictionary.removeValue(forKey: "UUID")

        switch node.kind {
        case .folder:
            let oldChildren = dictionary["Children"] as? [[String: Any]] ?? []
            dictionary["Title"] = node.title
            dictionary["WebBookmarkType"] = "WebBookmarkTypeList"
            dictionary["Children"] = encodeChildren(node.children, preserving: oldChildren)
            dictionary.removeValue(forKey: "URLString")
            dictionary.removeValue(forKey: "URIDictionary")
        case .bookmark:
            dictionary["WebBookmarkType"] = "WebBookmarkTypeLeaf"
            dictionary["URLString"] = node.url ?? ""
            var uri = dictionary["URIDictionary"] as? [String: Any] ?? [:]
            uri["title"] = node.title
            dictionary["URIDictionary"] = uri
            dictionary.removeValue(forKey: "Children")
            dictionary.removeValue(forKey: "Title")
        }
        return dictionary
    }
}
