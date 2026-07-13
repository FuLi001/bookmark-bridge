import BookmarkBridgeCore
import Foundation

enum InitializationSource {
    case safari
    case chrome
    case merge
}

struct CoordinatorSnapshot {
    var status: BridgeStatus
    var message: String
    var automaticSyncEnabled: Bool
    var safariTree: BookmarkNode?
    var chromeTree: BookmarkNode?
}

final class BridgeCoordinator {
    static let shared = BridgeCoordinator()

    var onStatusChanged: (() -> Void)?

    private let safariStore = SafariBookmarkStore()
    private let stateStore = SyncStateStore()
    private let queue = DispatchQueue(label: "BookmarkBridge.Coordinator")
    private var state: PersistedSyncState
    private var safariTree: BookmarkNode?
    private var chromeTree: BookmarkNode?
    private var pendingCommand: ChromeCommand?
    private var chromeCommandWaiters: [UUID: (LocalHTTPServer.Response) -> Void] = [:]
    private var status: BridgeStatus = .waitingForPermission
    private var message = "正在检查 Safari 权限"
    private var timer: DispatchSourceTimer?
    private var server: LocalHTTPServer?
    private var lastSafariFingerprint: SafariFileFingerprint?
    private var lastForcedSafariRead = Date.distantPast
    private var applyingSafariChange = false

    private init() {
        state = stateStore.load()
    }

    func start() {
        queue.async {
            do {
                let server = LocalHTTPServer { [weak self] method, path, body, completion in
                    guard let self else {
                        completion((500, Data()))
                        return
                    }
                    self.handleRequest(method: method, path: path, body: body, completion: completion)
                }
                try server.start()
                self.server = server
            } catch {
                self.setStatus(.error, "本地通信服务启动失败：\(error.localizedDescription)")
            }

            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: 3)
            timer.setEventHandler { [weak self] in self?.pollSafari() }
            timer.resume()
            self.timer = timer
        }
    }

    func snapshot() -> CoordinatorSnapshot {
        queue.sync {
            CoordinatorSnapshot(
                status: status,
                message: message,
                automaticSyncEnabled: state.automaticSyncEnabled,
                safariTree: safariTree,
                chromeTree: chromeTree
            )
        }
    }

    func setAutomaticSync(_ enabled: Bool) {
        queue.async {
            guard self.state.baseline != nil else {
                self.setStatus(.needsInitialization, "请先选择初始版本")
                return
            }
            self.state.automaticSyncEnabled = enabled
            self.persistState()
            self.evaluateChanges()
        }
    }

    func initialize(from source: InitializationSource) {
        queue.async {
            guard let safari = self.safariTree, let chrome = self.chromeTree else {
                self.refreshAvailabilityStatus()
                return
            }
            switch source {
            case .safari:
                self.queueChromeUpdate(safari)
                self.state.baseline = safari
                self.setStatus(.syncing, "正在以 Safari 个人收藏初始化 Chrome 书签栏")
            case .chrome:
                do {
                    try self.writeSafari(chrome)
                    self.state.baseline = chrome
                    self.safariTree = chrome
                    self.setStatus(.ready, "已以 Chrome 书签栏完成初始化")
                } catch {
                    self.setStatus(.error, "写入 Safari 失败：\(error.localizedDescription)")
                }
            case .merge:
                let merged = BookmarkTreeMerger.merge(safari, chrome)
                do {
                    if safari != merged {
                        try self.writeSafari(merged)
                        self.safariTree = merged
                    }
                    if chrome != merged {
                        self.queueChromeUpdate(merged)
                        self.setStatus(.syncing, "正在将安全合并结果写入两边")
                    } else {
                        self.setStatus(.ready, "已完成安全合并初始化")
                    }
                    self.state.baseline = merged
                } catch {
                    self.setStatus(.error, "安全合并失败：\(error.localizedDescription)")
                }
            }
            self.persistState()
        }
    }

    func resolveConflict(using source: InitializationSource) {
        initialize(from: source)
    }

    func checkNow() {
        queue.async {
            self.pollSafari(force: true)
            self.evaluateChanges()
        }
    }

    func backupDirectory() -> URL {
        safariStore.backupDirectory
    }

    private func pollSafari(force: Bool = false) {
        do {
            let fingerprint = try safariStore.fingerprint()
            let fallbackReadDue = Date().timeIntervalSince(lastForcedSafariRead) >= 3
            if force || fallbackReadDue || lastSafariFingerprint != fingerprint || safariTree == nil {
                let tree = try safariStore.readFavorites()
                safariTree = tree
                lastSafariFingerprint = try safariStore.fingerprint()
                lastForcedSafariRead = Date()
                if applyingSafariChange {
                    applyingSafariChange = false
                }
                evaluateChanges()
            } else {
                refreshAvailabilityStatus()
            }
        } catch {
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain && (nsError.code == 257 || nsError.code == 513) {
                setStatus(.waitingForPermission, "需要授予完全磁盘访问权限，才能读取 Safari 个人收藏")
            } else {
                setStatus(.error, "读取 Safari 失败：\(error.localizedDescription)")
            }
        }
    }

    private func evaluateChanges() {
        guard let safariTree else {
            refreshAvailabilityStatus()
            return
        }
        guard let chromeTree else {
            setStatus(.waitingForChrome, "等待 Chrome 扩展连接")
            return
        }
        guard let baseline = state.baseline else {
            setStatus(.needsInitialization, "请选择 Safari 或 Chrome 作为初始版本")
            return
        }

        let safariChanged = safariTree != baseline
        let chromeChanged = chromeTree != baseline

        if !safariChanged && !chromeChanged {
            setStatus(.ready, state.automaticSyncEnabled ? "自动同步已开启" : "同步已暂停")
        } else if safariChanged && chromeChanged {
            if safariTree == chromeTree {
                state.baseline = safariTree
                persistState()
                setStatus(.ready, "两边内容一致")
            } else {
                state.automaticSyncEnabled = false
                persistState()
                setStatus(.conflict, "Safari 和 Chrome 都发生了变化，已暂停自动同步")
            }
        } else if !state.automaticSyncEnabled {
            setStatus(.ready, "检测到未同步变化；自动同步当前关闭")
        } else if safariChanged {
            queueChromeUpdate(safariTree)
            setStatus(.syncing, "正在同步 Safari → Chrome")
        } else if chromeChanged {
            do {
                try writeSafari(chromeTree)
                self.safariTree = chromeTree
                state.baseline = chromeTree
                persistState()
                setStatus(.ready, "已同步 Chrome → Safari")
            } catch {
                setStatus(.error, "写入 Safari 失败：\(error.localizedDescription)")
            }
        }
    }

    private func writeSafari(_ tree: BookmarkNode) throws {
        applyingSafariChange = true
        _ = try safariStore.replaceFavorites(with: tree)
        lastSafariFingerprint = try safariStore.fingerprint()
        lastForcedSafariRead = Date()
    }

    private func queueChromeUpdate(_ tree: BookmarkNode) {
        if let chromeTree {
            do {
                try backupChrome(chromeTree)
            } catch {
                setStatus(.error, "无法备份 Chrome 书签：\(error.localizedDescription)")
                return
            }
        }
        state.commandRevision += 1
        pendingCommand = ChromeCommand(revision: state.commandRevision, tree: tree)
        persistState()
        completeChromeCommandWaiters()
    }

    private func backupChrome(_ tree: BookmarkNode) throws {
        let directory = safariStore.backupDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let url = directory.appendingPathComponent("Chrome-BookmarkBar-\(formatter.string(from: Date())).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(tree).write(to: url, options: .atomic)
    }

    private func handleRequest(
        method: String,
        path: String,
        body: Data,
        completion: @escaping (LocalHTTPServer.Response) -> Void
    ) {
        queue.async {
            let encoder = JSONEncoder()
            let decoder = JSONDecoder()
            do {
                if method == "POST" && path == "/chrome/snapshot" {
                    let snapshot = try decoder.decode(ChromeSnapshot.self, from: body)
                    self.chromeTree = snapshot.tree
                    self.evaluateChanges()
                    completion((204, Data()))
                    return
                }
                if method == "GET" && path == "/chrome/commands" {
                    if let command = self.pendingCommand {
                        completion((200, try encoder.encode(command)))
                    } else {
                        let waiterID = UUID()
                        self.chromeCommandWaiters[waiterID] = completion
                        self.queue.asyncAfter(deadline: .now() + 20) { [weak self] in
                            guard let waiter = self?.chromeCommandWaiters.removeValue(forKey: waiterID) else {
                                return
                            }
                            waiter((204, Data()))
                        }
                    }
                    return
                }
                if method == "POST" && path == "/chrome/ack" {
                    let acknowledgement = try decoder.decode(ChromeAcknowledgement.self, from: body)
                    if acknowledgement.success,
                       acknowledgement.revision == self.pendingCommand?.revision,
                       let tree = self.pendingCommand?.tree {
                        self.pendingCommand = nil
                        self.chromeTree = tree
                        self.state.baseline = tree
                        self.persistState()
                        self.setStatus(.ready, "Chrome 已完成同步")
                    } else if !acknowledgement.success {
                        self.setStatus(.error, "Chrome 同步失败：\(acknowledgement.message ?? "未知错误")")
                    }
                    completion((204, Data()))
                    return
                }
                if method == "GET" && path == "/status" {
                    let payload = ["status": self.status.rawValue, "message": self.message]
                    completion((200, try JSONSerialization.data(withJSONObject: payload)))
                    return
                }
                if method == "GET" && path == "/diagnostics" {
                    let safeMergeBookmarkCount: Any
                    if let safariTree = self.safariTree, let chromeTree = self.chromeTree {
                        safeMergeBookmarkCount = BookmarkTreeMerger.merge(safariTree, chromeTree).itemCount
                    } else {
                        safeMergeBookmarkCount = NSNull()
                    }
                    let payload: [String: Any] = [
                        "status": self.status.rawValue,
                        "automaticSyncEnabled": self.state.automaticSyncEnabled,
                        "hasBaseline": self.state.baseline != nil,
                        "treesEqual": self.safariTree != nil && self.safariTree == self.chromeTree,
                        "safeMergeBookmarkCount": safeMergeBookmarkCount,
                        "safari": self.diagnostics(for: self.safariTree),
                        "chrome": self.diagnostics(for: self.chromeTree),
                    ]
                    completion((200, try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])))
                    return
                }
                completion((404, Data("{\"error\":\"not found\"}".utf8)))
            } catch {
                completion((500, Data("{\"error\":\"\(error.localizedDescription)\"}".utf8)))
            }
        }
    }

    private func completeChromeCommandWaiters() {
        guard let command = pendingCommand,
              let data = try? JSONEncoder().encode(command) else {
            return
        }
        let waiters = chromeCommandWaiters.values
        chromeCommandWaiters.removeAll()
        for waiter in waiters {
            waiter((200, data))
        }
    }

    private func refreshAvailabilityStatus() {
        if safariTree == nil {
            setStatus(.waitingForPermission, "需要授予完全磁盘访问权限，才能读取 Safari 个人收藏")
        } else if chromeTree == nil {
            setStatus(.waitingForChrome, "等待 Chrome 扩展连接")
        } else if state.baseline == nil {
            setStatus(.needsInitialization, "请选择 Safari 或 Chrome 作为初始版本")
        }
    }

    private func diagnostics(for tree: BookmarkNode?) -> [String: Any] {
        guard let tree else { return ["connected": false] }
        return [
            "connected": true,
            "bookmarkCount": tree.itemCount,
            "folderCount": max(0, tree.folderCount - 1),
            "topLevelFolders": tree.children.filter { $0.kind == .folder }.map(\.title),
            "topLevelBookmarks": tree.children.filter { $0.kind == .bookmark }.count,
        ]
    }

    private func persistState() {
        do {
            try stateStore.save(state)
        } catch {
            setStatus(.error, "无法保存同步状态：\(error.localizedDescription)")
        }
    }

    private func setStatus(_ status: BridgeStatus, _ message: String) {
        let changed = self.status != status || self.message != message
        self.status = status
        self.message = message
        if changed {
            DispatchQueue.main.async { [weak self] in self?.onStatusChanged?() }
        }
    }
}
