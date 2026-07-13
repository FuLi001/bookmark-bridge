# Bookmark Bridge

在同一台 Mac 上自动双向同步 Safari“个人收藏”和 Chrome“书签栏”，同时保留两个浏览器原生的根目录层级。

Bookmark Bridge maps Safari **Favorites** to Chrome **Bookmark Bar** and keeps their children in two-way sync without copying either browser's root folder.
本项目的初衷是，在mac上本地实时自动双向同步Safari和Chrome的书签。虽然苹果官方为Chrome提供了iCloud插件，也可以实现类似功能，但官方插件存在同步有延迟、不同浏览器目录层级不同导致重复备份、不同浏览器目录层级不同导致书签异常散落在其它书签文件夹等问题。而本项目基于作者的需求，指定了同步目录为Safari的个人收藏文件夹以及Chrome书签栏，表现形式为两个浏览器的顶部书签栏实时同步，符合大部分人的使用习惯。
<img width="1352" height="207" alt="Snipaste_2026-07-14_02-33-11" src="https://github.com/user-attachments/assets/9b3e132c-7760-4fb6-892f-077c242c4da2" />

## 特点

- 双向同步文件夹、书签标题、网址和顺序
- Safari“个人收藏”与 Chrome“书签栏”直接映射，不制造额外嵌套层级
- Chrome 变化通过书签事件上报，Safari 每 3 秒进行本地只读比较
- Chrome 到 Safari 通常约需 1–4 秒；Safari 到 Chrome 通常约需 2–6 秒，偶尔可能需要几十秒
- 首次使用可选择安全合并、采用 Safari 或采用 Chrome
- 两边同时发生不同变化时暂停同步，不擅自覆盖
- 每次写入 Safari 前自动备份；修改 Chrome 前保存 JSON 备份
- 只通过 `127.0.0.1:17315` 本地通信，不上传云端
- 支持 Apple 芯片与 Intel Mac，最低 macOS 13

## 同步范围

| Safari | Chrome | 是否同步 |
| --- | --- | --- |
| 个人收藏 | 书签栏 | 是 |
| 阅读列表 | - | 否 |
| - | 其他书签 | 否 |
| - | 移动设备书签 | 否 |

## 安装

1. 从 [Releases](../../releases) 下载最新压缩包并解压。
2. 将整个 `Bookmark Bridge 1.0.0` 文件夹移入“应用程序”。
3. 按住 Control 点击 `Bookmark Bridge.app`，选择“打开”。应用为自签名版本，首次运行可能需要在“系统设置 > 隐私与安全性”中选择“仍要打开”。
4. 从菜单栏书签图标打开完全磁盘访问权限设置，为 Bookmark Bridge 授权后重启应用。
5. 打开 `chrome://extensions`，开启开发者模式，选择“加载已解压的扩展程序”，加载 `Bookmark Bridge Chrome Extension` 文件夹。
6. 等菜单显示两边数量后，优先选择“初始化：安全合并两边”，检查结果并开启“自动双向同步”。

安装包内的 `使用说明.txt` 包含完整教程、冲突处理、备份与卸载步骤。

## 运行条件

- Bookmark Bridge 菜单栏应用必须运行，建议加入 macOS 登录项。
- Safari 不必一直开启。
- Chrome 关闭期间无法执行 Chrome 侧修改，重新打开后会继续同步。
- Mac 睡眠期间暂停，唤醒后恢复。

### 为什么 Safari 到 Chrome 有时较慢

Safari 没有提供公开的书签变更通知接口。Bookmark Bridge 只能定期读取 Safari 的本地书签文件并比较内容，而 Safari 有时会延迟把编辑结果写入磁盘，因此 Safari 到 Chrome 通常需要几秒，偶尔可能延长到几十秒。Chrome 的 Manifest V3 后台扩展被系统休眠时，也可能叠加最多约 30 秒的等待。程序检测到实际变化后才会写入另一边，不会为了追求速度持续改写书签文件。

## 安全设计

Safari 没有提供公开的书签扩展写入 API，因此桌面程序会在获得完全磁盘访问权限后读写 `~/Library/Safari/Bookmarks.plist`。每次写入前都会保存原文件备份。Chrome 侧只使用官方 `chrome.bookmarks` API。

默认备份目录：

```text
~/Library/Application Support/BookmarkBridge/Backups
```

尽管程序带有备份和冲突保护，首次使用前仍建议分别从 Safari 与 Chrome 手动导出一次书签。

## 从源码构建

需要 macOS 13+、Swift 6 和 macOS SDK。

```bash
swift run BookmarkBridgeChecks
zsh scripts/package-app.sh
```

生成内容：

```text
outputs/Bookmark Bridge.app
outputs/Bookmark Bridge Chrome Extension/
```

构建 Apple 芯片与 Intel 通用分享包：

```bash
zsh scripts/package-distribution.sh
```

## 项目结构

```text
Sources/BookmarkBridgeCore/   书签模型、合并和 Safari 存储
Sources/BookmarkBridge/       菜单栏应用与本地 HTTP 服务
ChromeExtension/              Chrome Manifest V3 扩展
Sources/BookmarkBridgeChecks/ 无需真实浏览器的安全检查
Distribution/                 分享包内的中文说明
scripts/                      构建与打包脚本
```

## 隐私

项目不包含遥测、账号系统或云端服务。Safari 与 Chrome 的书签内容仅在本机处理。源码、Issue 和日志中请勿提交真实书签文件或备份。

## 许可证

[MIT License](LICENSE)
