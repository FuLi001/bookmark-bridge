import Foundation

public enum SafariStoreError: LocalizedError {
    case invalidPropertyList
    case folderNotFound(String)
    case folderChildrenMissing(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPropertyList:
            return "Safari 书签文件格式无法识别"
        case let .folderNotFound(path):
            return "找不到 Safari 同步目录：\(path)"
        case let .folderChildrenMissing(path):
            return "Safari 同步目录缺少子项：\(path)"
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

public struct SafariFolderSnapshot {
    public let tree: BookmarkNode
    public let selectedFolder: BookmarkFolderChoice
    public let folders: [BookmarkFolderChoice]
}

public final class SafariBookmarkStore {
    public static let defaultFolderID = SyncFolderConfiguration.defaultSafariFolderID

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
        try readFolder(id: Self.defaultFolderID).tree
    }

    public func readFolder(id: String) throws -> SafariFolderSnapshot {
        let root = try readRoot()
        guard let children = root["Children"] as? [[String: Any]] else {
            throw SafariStoreError.invalidPropertyList
        }

        let located = Self.locateFolders(in: children)
        guard let selected = located.first(where: { $0.choice.id == id }) else {
            throw SafariStoreError.folderNotFound(id)
        }
        guard let selectedChildren = selected.dictionary["Children"] as? [[String: Any]] else {
            throw SafariStoreError.folderChildrenMissing(selected.choice.displayPath)
        }

        return SafariFolderSnapshot(
            tree: .folder("root", children: selectedChildren.compactMap(Self.decodeNode)),
            selectedFolder: selected.choice,
            folders: located.map(\.choice)
        )
    }

    @discardableResult
    public func replaceFavorites(with tree: BookmarkNode) throws -> URL {
        try replaceFolder(id: Self.defaultFolderID, with: tree)
    }

    @discardableResult
    public func replaceFolder(id: String, with tree: BookmarkNode) throws -> URL {
        let originalData = try Data(contentsOf: bookmarksURL)
        let plist = try PropertyListSerialization.propertyList(from: originalData, options: [], format: nil)
        guard var root = plist as? [String: Any],
              var rootChildren = root["Children"] as? [[String: Any]] else {
            throw SafariStoreError.invalidPropertyList
        }

        var replaced = false
        for index in rootChildren.indices {
            let isFavorites = Self.isFavoritesFolder(rootChildren[index])
            let title = Self.displayTitle(for: rootChildren[index], isFavorites: isFavorites)
            let result = Self.replacingFolder(
                rootChildren[index],
                targetID: id,
                replacement: tree,
                path: [title],
                indexPath: [index],
                isFavorites: isFavorites
            )
            rootChildren[index] = result.dictionary
            if result.replaced {
                replaced = true
                break
            }
        }
        guard replaced else { throw SafariStoreError.folderNotFound(id) }
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

    private func readRoot() throws -> [String: Any] {
        let data = try Data(contentsOf: bookmarksURL)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let root = plist as? [String: Any] else {
            throw SafariStoreError.invalidPropertyList
        }
        return root
    }

    private struct LocatedFolder {
        let choice: BookmarkFolderChoice
        let dictionary: [String: Any]
    }

    private static func locateFolders(in dictionaries: [[String: Any]],
                                      parentPath: [String] = [],
                                      parentIndexPath: [Int] = []) -> [LocatedFolder] {
        var result: [LocatedFolder] = []
        for (index, dictionary) in dictionaries.enumerated() {
            guard isFolder(dictionary) else { continue }
            if parentPath.isEmpty && isExcludedRootFolder(dictionary) { continue }
            let indexPath = parentIndexPath + [index]
            let isFavorites = parentPath.isEmpty && isFavoritesFolder(dictionary)
            let title = displayTitle(for: dictionary, isFavorites: isFavorites)
            let path = parentPath + [title]
            let choice = BookmarkFolderChoice(
                id: folderID(for: dictionary, path: path, indexPath: indexPath, isFavorites: isFavorites),
                title: title,
                path: path
            )
            result.append(LocatedFolder(choice: choice, dictionary: dictionary))
            let children = dictionary["Children"] as? [[String: Any]] ?? []
            result.append(contentsOf: locateFolders(
                in: children,
                parentPath: path,
                parentIndexPath: indexPath
            ))
        }
        return result
    }

    private static func replacingFolder(_ dictionary: [String: Any],
                                        targetID: String,
                                        replacement: BookmarkNode,
                                        path: [String],
                                        indexPath: [Int],
                                        isFavorites: Bool) -> (dictionary: [String: Any], replaced: Bool) {
        var dictionary = dictionary
        let currentID = folderID(
            for: dictionary,
            path: path,
            indexPath: indexPath,
            isFavorites: isFavorites
        )
        if currentID == targetID {
            let existing = dictionary["Children"] as? [[String: Any]] ?? []
            dictionary["Children"] = encodeChildren(replacement.children, preserving: existing)
            return (dictionary, true)
        }

        guard var children = dictionary["Children"] as? [[String: Any]] else {
            return (dictionary, false)
        }
        for index in children.indices {
            guard isFolder(children[index]) else { continue }
            let childTitle = displayTitle(for: children[index], isFavorites: false)
            let result = replacingFolder(
                children[index],
                targetID: targetID,
                replacement: replacement,
                path: path + [childTitle],
                indexPath: indexPath + [index],
                isFavorites: false
            )
            children[index] = result.dictionary
            if result.replaced {
                dictionary["Children"] = children
                return (dictionary, true)
            }
        }
        return (dictionary, false)
    }

    private static func folderID(for dictionary: [String: Any],
                                 path: [String],
                                 indexPath: [Int],
                                 isFavorites: Bool) -> String {
        if isFavorites { return defaultFolderID }
        if let uuid = dictionary["WebBookmarkUUID"] as? String ?? dictionary["UUID"] as? String {
            return "safari:uuid:\(uuid)"
        }
        if let identifier = dictionary["WebBookmarkIdentifier"] as? String
            ?? dictionary["Identifier"] as? String {
            return "safari:identifier:\(identifier)"
        }
        return "safari:path:\(path.joined(separator: "\u{1F}"))#\(indexPath.map(String.init).joined(separator: "."))"
    }

    private static func displayTitle(for dictionary: [String: Any], isFavorites: Bool) -> String {
        if isFavorites { return "个人收藏" }
        return dictionary["Title"] as? String ?? "未命名文件夹"
    }

    private static func isFolder(_ dictionary: [String: Any]) -> Bool {
        dictionary["Children"] != nil || dictionary["WebBookmarkType"] as? String == "WebBookmarkTypeList"
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

    private static func isExcludedRootFolder(_ dictionary: [String: Any]) -> Bool {
        let identifiers = [
            dictionary["Title"] as? String ?? "",
            dictionary["WebBookmarkIdentifier"] as? String ?? "",
            dictionary["Identifier"] as? String ?? "",
        ].map { $0.lowercased() }
        return identifiers.contains(where: {
            $0.contains("readinglist") || $0.contains("reading list") || $0.contains("阅读列表")
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
                    return isFolder(existingNode) && existingNode["Title"] as? String == node.title
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
