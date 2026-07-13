import Foundation

public struct BookmarkNode: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case folder
        case bookmark
    }

    public var kind: Kind
    public var title: String
    public var url: String?
    public var children: [BookmarkNode]

    public init(kind: Kind, title: String, url: String? = nil, children: [BookmarkNode] = []) {
        self.kind = kind
        self.title = title
        self.url = url
        self.children = children
    }

    public static func folder(_ title: String, children: [BookmarkNode] = []) -> BookmarkNode {
        BookmarkNode(kind: .folder, title: title, children: children)
    }

    public static func bookmark(_ title: String, url: String) -> BookmarkNode {
        BookmarkNode(kind: .bookmark, title: title, url: url)
    }

    public var itemCount: Int {
        children.reduce(kind == .bookmark ? 1 : 0) { $0 + $1.itemCount }
    }

    public var folderCount: Int {
        children.reduce(kind == .folder ? 1 : 0) { $0 + $1.folderCount }
    }
}

public struct BookmarkFolderChoice: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var path: [String]

    public init(id: String, title: String, path: [String]) {
        self.id = id
        self.title = title
        self.path = path
    }

    public var displayPath: String {
        path.joined(separator: " › ")
    }
}

public struct ChromeSnapshot: Codable, Sendable {
    public var tree: BookmarkNode
    public var folderID: String?
    public var folderPath: String?
    public var folders: [BookmarkFolderChoice]?

    public init(tree: BookmarkNode,
                folderID: String? = nil,
                folderPath: String? = nil,
                folders: [BookmarkFolderChoice]? = nil) {
        self.tree = tree
        self.folderID = folderID
        self.folderPath = folderPath
        self.folders = folders
    }
}

public struct ChromeCommand: Codable, Sendable {
    public var revision: Int
    public var tree: BookmarkNode
    public var folderID: String?

    public init(revision: Int, tree: BookmarkNode, folderID: String? = nil) {
        self.revision = revision
        self.tree = tree
        self.folderID = folderID
    }
}

public struct ChromeAcknowledgement: Codable, Sendable {
    public var revision: Int
    public var success: Bool
    public var message: String?

    public init(revision: Int, success: Bool, message: String? = nil) {
        self.revision = revision
        self.success = success
        self.message = message
    }
}
