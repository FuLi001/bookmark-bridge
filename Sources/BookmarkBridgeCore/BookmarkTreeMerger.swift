import Foundation

public enum BookmarkTreeMerger {
    public static func merge(_ left: BookmarkNode, _ right: BookmarkNode) -> BookmarkNode {
        BookmarkNode.folder("root", children: mergeChildren(left.children, right.children))
    }

    private static func mergeChildren(_ left: [BookmarkNode], _ right: [BookmarkNode]) -> [BookmarkNode] {
        var result = left
        var matchedLeftIndexes = Set<Int>()

        for rightNode in right {
            if let matchIndex = result.indices.first(where: { index in
                !matchedLeftIndexes.contains(index) && nodesMatch(result[index], rightNode)
            }) {
                matchedLeftIndexes.insert(matchIndex)
                if rightNode.kind == .folder {
                    result[matchIndex].children = mergeChildren(result[matchIndex].children, rightNode.children)
                } else if result[matchIndex].title.isEmpty && !rightNode.title.isEmpty {
                    result[matchIndex].title = rightNode.title
                }
            } else {
                result.append(rightNode)
            }
        }
        return result
    }

    private static func nodesMatch(_ left: BookmarkNode, _ right: BookmarkNode) -> Bool {
        guard left.kind == right.kind else { return false }
        switch left.kind {
        case .folder:
            return left.title == right.title
        case .bookmark:
            return left.url == right.url
        }
    }
}
