import AppKit
import BookmarkBridgeCore
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let coordinator = BridgeCoordinator.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "bookmark", accessibilityDescription: "Bookmark Bridge")
        statusItem.button?.toolTip = "Bookmark Bridge"
        coordinator.onStatusChanged = { [weak self] in self?.rebuildMenu() }
        rebuildMenu()
        coordinator.start()
    }

    private func rebuildMenu() {
        let snapshot = coordinator.snapshot()
        let menu = NSMenu()

        let status = NSMenuItem(title: snapshot.message, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        if let safari = snapshot.safariTree, let chrome = snapshot.chromeTree {
            let counts = NSMenuItem(
                title: "Safari \(safari.itemCount) 项 · Chrome \(chrome.itemCount) 项",
                action: nil,
                keyEquivalent: ""
            )
            counts.isEnabled = false
            menu.addItem(counts)
        }

        menu.addItem(.separator())

        let automatic = NSMenuItem(title: "自动双向同步", action: #selector(toggleAutomaticSync(_:)), keyEquivalent: "")
        automatic.target = self
        automatic.state = snapshot.automaticSyncEnabled ? .on : .off
        automatic.isEnabled = snapshot.status == .ready
        menu.addItem(automatic)

        let check = NSMenuItem(title: "立即检查", action: #selector(checkNow), keyEquivalent: "r")
        check.target = self
        menu.addItem(check)

        menu.addItem(.separator())

        let folderHeader = NSMenuItem(title: "同步目录", action: nil, keyEquivalent: "")
        folderHeader.isEnabled = false
        menu.addItem(folderHeader)

        let safariFolder = NSMenuItem(
            title: "Safari：\(snapshot.selectedSafariFolderPath)",
            action: nil,
            keyEquivalent: ""
        )
        safariFolder.submenu = folderMenu(
            choices: snapshot.safariFolders,
            selectedID: snapshot.selectedSafariFolderID,
            action: #selector(selectSafariFolder(_:))
        )
        safariFolder.isEnabled = !snapshot.safariFolders.isEmpty
        menu.addItem(safariFolder)

        let chromeFolder = NSMenuItem(
            title: "Chrome：\(snapshot.selectedChromeFolderPath)",
            action: nil,
            keyEquivalent: ""
        )
        chromeFolder.submenu = folderMenu(
            choices: snapshot.chromeFolders,
            selectedID: snapshot.selectedChromeFolderID,
            action: #selector(selectChromeFolder(_:))
        )
        chromeFolder.isEnabled = !snapshot.chromeFolders.isEmpty
        menu.addItem(chromeFolder)

        let restoreDefaults = NSMenuItem(
            title: "恢复默认目录（个人收藏 ↔ 书签栏）",
            action: #selector(restoreDefaultFolders),
            keyEquivalent: ""
        )
        restoreDefaults.target = self
        restoreDefaults.isEnabled = snapshot.selectedSafariFolderID != SyncFolderConfiguration.defaultSafariFolderID
            || snapshot.selectedChromeFolderID != SyncFolderConfiguration.defaultChromeFolderID
        menu.addItem(restoreDefaults)

        menu.addItem(.separator())

        let merge = NSMenuItem(title: "初始化：安全合并两边", action: #selector(mergeBoth), keyEquivalent: "")
        merge.target = self
        merge.isEnabled = snapshot.safariTree != nil && snapshot.chromeTree != nil
        menu.addItem(merge)

        let safariSourceTitle = snapshot.status == .conflict ? "解决冲突：采用 Safari" : "初始化：采用 Safari"
        let safariSource = NSMenuItem(title: safariSourceTitle, action: #selector(useSafari), keyEquivalent: "")
        safariSource.target = self
        safariSource.isEnabled = snapshot.safariTree != nil && snapshot.chromeTree != nil
        menu.addItem(safariSource)

        let chromeSourceTitle = snapshot.status == .conflict ? "解决冲突：采用 Chrome" : "初始化：采用 Chrome"
        let chromeSource = NSMenuItem(title: chromeSourceTitle, action: #selector(useChrome), keyEquivalent: "")
        chromeSource.target = self
        chromeSource.isEnabled = snapshot.safariTree != nil && snapshot.chromeTree != nil
        menu.addItem(chromeSource)

        let backups = NSMenuItem(title: "打开备份目录", action: #selector(openBackups), keyEquivalent: "")
        backups.target = self
        menu.addItem(backups)

        let privacy = NSMenuItem(title: "打开完全磁盘访问权限设置", action: #selector(openPrivacySettings), keyEquivalent: "")
        privacy.target = self
        menu.addItem(privacy)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 Bookmark Bridge", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func toggleAutomaticSync(_ sender: NSMenuItem) {
        coordinator.setAutomaticSync(sender.state != .on)
    }

    @objc private func checkNow() {
        coordinator.checkNow()
    }

    @objc private func useSafari() {
        let snapshot = coordinator.snapshot()
        confirmReplacement(
            source: "Safari：\(snapshot.selectedSafariFolderPath)",
            destination: "Chrome：\(snapshot.selectedChromeFolderPath)"
        ) {
            self.coordinator.resolveConflict(using: .safari)
        }
    }

    @objc private func useChrome() {
        let snapshot = coordinator.snapshot()
        confirmReplacement(
            source: "Chrome：\(snapshot.selectedChromeFolderPath)",
            destination: "Safari：\(snapshot.selectedSafariFolderPath)"
        ) {
            self.coordinator.resolveConflict(using: .chrome)
        }
    }

    @objc private func mergeBoth() {
        let snapshot = coordinator.snapshot()
        let safariCount = snapshot.safariTree?.itemCount ?? 0
        let chromeCount = snapshot.chromeTree?.itemCount ?? 0
        let mergedCount = if let safari = snapshot.safariTree, let chrome = snapshot.chromeTree {
            BookmarkTreeMerger.merge(safari, chrome).itemCount
        } else { 0 }

        let alert = NSAlert()
        alert.messageText = "安全合并 Safari 与 Chrome？"
        alert.informativeText = "Safari 有 \(safariCount) 个书签，Chrome 有 \(chromeCount) 个；合并后预计 \(mergedCount) 个。两边独有项都会保留，同一文件夹内的相同网址只保留一份。写入前会分别备份。"
        alert.addButton(withTitle: "合并")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            coordinator.initialize(from: .merge)
        }
    }

    @objc private func openBackups() {
        let url = coordinator.backupDirectory()
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    @objc private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func selectSafariFolder(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        confirmFolderChange(browser: "Safari", path: sender.title) {
            self.coordinator.selectSafariFolder(id: id, path: sender.title)
        }
    }

    @objc private func selectChromeFolder(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        confirmFolderChange(browser: "Chrome", path: sender.title) {
            self.coordinator.selectChromeFolder(id: id, path: sender.title)
        }
    }

    @objc private func restoreDefaultFolders() {
        confirmFolderChange(browser: "两个浏览器", path: "个人收藏 ↔ 书签栏") {
            self.coordinator.restoreDefaultFolders()
        }
    }

    private func folderMenu(choices: [BookmarkFolderChoice],
                            selectedID: String,
                            action: Selector) -> NSMenu {
        let menu = NSMenu()
        for choice in choices {
            let item = NSMenuItem(title: choice.displayPath, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = choice.id
            item.state = choice.id == selectedID ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    private func confirmFolderChange(browser: String, path: String, action: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "更换\(browser)同步目录？"
        alert.informativeText = "将改为“\(path)”。自动同步会暂停，旧同步基线会清除，但现在不会修改任何书签。选择后请重新初始化两边。"
        alert.addButton(withTitle: "更换目录")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn { action() }
    }

    private func confirmReplacement(source: String, destination: String, action: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "采用 \(source)？"
        alert.informativeText = "\(destination) 的内部内容将调整为与 \(source) 一致。根目录名称不会改变，Safari 写入前会自动备份。"
        alert.addButton(withTitle: "继续")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn { action() }
    }
}

if CommandLine.arguments.contains("--headless") {
    BridgeCoordinator.shared.start()
    RunLoop.main.run()
} else {
    let application = NSApplication.shared
    let delegate = AppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
}
