import BookmarkBridgeCore
import Foundation

func leaf(title: String, url: String) -> [String: Any] {
    [
        "WebBookmarkType": "WebBookmarkTypeLeaf",
        "URLString": url,
        "URIDictionary": ["title": title],
        "UUID": UUID().uuidString
    ]
}

func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else {
        throw NSError(domain: "BookmarkBridgeChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
defer { try? FileManager.default.removeItem(at: temporary) }

let safariDirectory = temporary.appendingPathComponent("Library/Safari")
let support = temporary.appendingPathComponent("Support")
try FileManager.default.createDirectory(at: safariDirectory, withIntermediateDirectories: true)

let original: [String: Any] = [
    "Title": "",
    "WebBookmarkType": "WebBookmarkTypeList",
    "Children": [
        [
            "Title": "BookmarksBar",
            "WebBookmarkType": "WebBookmarkTypeList",
            "Children": [leaf(title: "旧页面", url: "https://old.example")]
        ],
        [
            "Title": "BookmarksMenu",
            "WebBookmarkType": "WebBookmarkTypeList",
            "Children": [leaf(title: "保持不变", url: "https://untouched.example")]
        ]
    ]
]
let data = try PropertyListSerialization.data(fromPropertyList: original, format: .binary, options: 0)
try data.write(to: safariDirectory.appendingPathComponent("Bookmarks.plist"))

let store = SafariBookmarkStore(homeDirectory: temporary, applicationSupport: support)
try check(store.readFavorites().title == "root", "Safari 根目录没有转换为内部虚拟根")
try check(store.readFavorites().children.first?.title == "旧页面", "读取 Safari 书签失败")

let replacement = BookmarkNode.folder("root", children: [
    .folder("工作学习", children: [
        .bookmark("OpenAI", url: "https://openai.com")
    ])
])
let backup = try store.replaceFavorites(with: replacement)
try check(FileManager.default.fileExists(atPath: backup.path), "写入前未创建备份")

let result = try store.readFavorites()
try check(result.children.first?.title == "工作学习", "文件夹替换失败")
try check(result.children.first?.children.first?.url == "https://openai.com", "书签替换失败")

let written = try PropertyListSerialization.propertyList(
    from: Data(contentsOf: store.bookmarksURL), options: [], format: nil
) as! [String: Any]
let roots = written["Children"] as! [[String: Any]]
let writtenFolder = (roots[0]["Children"] as! [[String: Any]])[0]
let writtenLeaf = (writtenFolder["Children"] as! [[String: Any]])[0]
try check(writtenFolder["WebBookmarkUUID"] as? String != nil, "新文件夹缺少 Safari WebBookmarkUUID")
try check(writtenLeaf["WebBookmarkUUID"] as? String != nil, "新书签缺少 Safari WebBookmarkUUID")
try check(writtenFolder["UUID"] == nil && writtenLeaf["UUID"] == nil, "错误写入了通用 UUID 字段")
let menuChildren = roots[1]["Children"] as! [[String: Any]]
try check(menuChildren[0]["URLString"] as? String == "https://untouched.example", "错误修改了 Safari 其他根目录")

let firstFingerprint = try store.fingerprint()
let preservedDate = firstFingerprint.modificationDate ?? Date(timeIntervalSince1970: 1_700_000_000)
var changedBytes = try Data(contentsOf: store.bookmarksURL)
changedBytes.append(0)
try changedBytes.write(to: store.bookmarksURL, options: .atomic)
try FileManager.default.setAttributes([.modificationDate: preservedDate], ofItemAtPath: store.bookmarksURL.path)
let secondFingerprint = try store.fingerprint()
let firstFingerprintIgnoringDate = SafariFileFingerprint(
    modificationDate: secondFingerprint.modificationDate,
    fileSize: firstFingerprint.fileSize,
    systemFileNumber: firstFingerprint.systemFileNumber
)
try check(firstFingerprintIgnoringDate != secondFingerprint, "文件指纹未能在忽略修改时间后发现内容变化")

let left = BookmarkNode.folder("root", children: [
    .folder("工作学习", children: [
        .bookmark("共同项目", url: "https://shared.example"),
        .bookmark("仅 Safari", url: "https://safari.example")
    ])
])
let right = BookmarkNode.folder("root", children: [
    .folder("工作学习", children: [
        .bookmark("共同项目", url: "https://shared.example"),
        .bookmark("仅 Chrome", url: "https://chrome.example")
    ]),
    .folder("Chrome 独有目录", children: [])
])
let merged = BookmarkTreeMerger.merge(left, right)
try check(merged.itemCount == 3, "安全合并没有正确去重或保留独有项")
try check(merged.children.count == 2, "安全合并没有保留独有目录")

print("Bookmark Bridge checks passed")
