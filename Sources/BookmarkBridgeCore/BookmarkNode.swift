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

public struct ChromeSnapshot: Codable, Sendable {
    public var tree: BookmarkNode

    public init(tree: BookmarkNode) {
        self.tree = tree
    }
}

public struct ChromeCommand: Codable, Sendable {
    public var revision: Int
    public var tree: BookmarkNode

    public init(revision: Int, tree: BookmarkNode) {
        self.revision = revision
        self.tree = tree
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
