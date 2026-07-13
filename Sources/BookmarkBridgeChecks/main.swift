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
            "WebBookmarkUUID": "menu-root",
            "Children": [
                [
                    "Title": "自定义同步",
                    "WebBookmarkType": "WebBookmarkTypeList",
                    "WebBookmarkUUID": "custom-folder",
                    "Children": [leaf(title: "自定义旧页面", url: "https://custom-old.example")]
                ],
                leaf(title: "保持不变", url: "https://untouched.example")
            ]
        ],
        [
            "Title": "com.apple.ReadingList",
            "WebBookmarkIdentifier": "com.apple.ReadingList",
            "WebBookmarkType": "WebBookmarkTypeList",
            "Children": [leaf(title: "阅读项目", url: "https://reading.example")]
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
try check(menuChildren[1]["URLString"] as? String == "https://untouched.example", "错误修改了 Safari 其他根目录")

let customFolderID = "safari:uuid:custom-folder"
let customSnapshot = try store.readFolder(id: customFolderID)
try check(customSnapshot.selectedFolder.displayPath == "BookmarksMenu › 自定义同步", "自定义目录路径识别错误")
try check(customSnapshot.tree.children.first?.url == "https://custom-old.example", "读取自定义 Safari 目录失败")
try check(customSnapshot.folders.contains(where: { $0.id == SafariBookmarkStore.defaultFolderID }), "目录清单缺少默认个人收藏")
try check(!customSnapshot.folders.contains(where: { $0.displayPath.lowercased().contains("readinglist") }), "错误地把阅读列表作为同步目录")

let customReplacement = BookmarkNode.folder("root", children: [
    .bookmark("自定义新页面", url: "https://custom-new.example")
])
_ = try store.replaceFolder(id: customFolderID, with: customReplacement)
try check(try store.readFolder(id: customFolderID).tree.children.first?.url == "https://custom-new.example", "自定义目录替换失败")
try check(try store.readFavorites() == replacement, "修改自定义目录时错误改动了个人收藏")

let legacyStateData = Data("""
{"automaticSyncEnabled":true,"baseline":null,"commandRevision":7}
""".utf8)
let migratedState = try JSONDecoder().decode(PersistedSyncState.self, from: legacyStateData)
try check(migratedState.folders.safariFolderID == SyncFolderConfiguration.defaultSafariFolderID, "旧状态未迁移到默认 Safari 目录")
try check(migratedState.folders.chromeFolderID == SyncFolderConfiguration.defaultChromeFolderID, "旧状态未迁移到默认 Chrome 目录")
try check(migratedState.automaticSyncEnabled && migratedState.commandRevision == 7, "旧状态迁移丢失已有设置")

let customConfiguration = SyncFolderConfiguration(
    safariFolderID: customFolderID,
    safariFolderPath: "BookmarksMenu › 自定义同步",
    chromeFolderID: "42",
    chromeFolderPath: "书签栏 › 自定义同步",
    revision: 3
)
let configuredState = PersistedSyncState(folders: customConfiguration)
let decodedConfiguredState = try JSONDecoder().decode(
    PersistedSyncState.self,
    from: JSONEncoder().encode(configuredState)
)
try check(decodedConfiguredState.folders == customConfiguration, "自定义目录配置无法持久化")

let targetedCommand = ChromeCommand(revision: 9, tree: replacement, folderID: "42")
let decodedCommand = try JSONDecoder().decode(ChromeCommand.self, from: JSONEncoder().encode(targetedCommand))
try check(decodedCommand.folderID == "42", "Chrome 同步命令没有绑定目标目录")

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
