# Bookmark Bridge

<p align="center">
  <a href="./README.md">简体中文</a> | <strong>English</strong>
</p>

Automatically synchronize Safari **Favorites** and Chrome **Bookmark Bar** in both directions on the same Mac while preserving each browser's native root folder hierarchy.

This project was created to provide local, automatic, two-way bookmark synchronization between Safari and Chrome on macOS. Apple's official iCloud extension for Chrome offers similar functionality, but users may encounter synchronization delays, duplicate bookmarks caused by mismatched folder hierarchies, or bookmarks scattered into folders such as **Other Bookmarks**. Bookmark Bridge was built around the author's practical needs: it deliberately maps Safari **Favorites** to Chrome **Bookmark Bar**, keeping the contents of both browsers' top bookmark bars synchronized in a way that matches everyday browsing habits.

<img width="1352" height="207" alt="Bookmark bars synchronized between Safari and Chrome" src="https://github.com/user-attachments/assets/9b3e132c-7760-4fb6-892f-077c242c4da2" />

## Features

- Synchronizes folders, bookmark titles, URLs, and ordering in both directions
- Maps Safari Favorites directly to Chrome Bookmark Bar without creating an extra nested root folder
- Reports Chrome changes through bookmark events and compares Safari's local bookmark data every 3 seconds
- Chrome to Safari usually takes about 1–4 seconds; Safari to Chrome usually takes about 2–6 seconds and may occasionally take tens of seconds
- Offers safe merge, use Safari, or use Chrome during initial setup
- Pauses instead of guessing when both sides contain different changes
- Backs up Safari before every write and saves a JSON backup before changing Chrome
- Communicates only through `127.0.0.1:17315`; no data is uploaded to the cloud
- Supports both Apple silicon and Intel Macs running macOS 13 or later

## Sync Scope

| Safari | Chrome | Synchronized |
| --- | --- | --- |
| Favorites | Bookmark Bar | Yes |
| Reading List | - | No |
| - | Other Bookmarks | No |
| - | Mobile Bookmarks | No |

## Installation

1. Download and extract the latest archive from [Releases](https://github.com/FuLi001/bookmark-bridge/releases/latest).
2. Move the entire `Bookmark Bridge 1.0.0` folder into Applications.
3. Control-click `Bookmark Bridge.app` and choose **Open**. The app is self-signed, so its first launch may require choosing **Open Anyway** in **System Settings > Privacy & Security**.
4. Use the bookmark icon in the menu bar to open Full Disk Access settings, grant access to Bookmark Bridge, and restart the app.
5. Open `chrome://extensions`, enable **Developer mode**, choose **Load unpacked**, and select the `Bookmark Bridge Chrome Extension` folder.
6. After the menu shows bookmark counts for both browsers, choose **初始化：安全合并两边** (Initialize: Safely Merge Both), review the result, and enable **自动双向同步** (Automatic Two-Way Sync).

The release archive includes `使用说明.txt` with a complete Chinese guide covering setup, conflicts, backups, and removal.

## Runtime Requirements

- The Bookmark Bridge menu bar app must remain running. Adding it to macOS Login Items is recommended.
- Safari does not need to remain open.
- Chrome-side changes cannot be applied while Chrome is closed; synchronization resumes when Chrome is reopened.
- Synchronization pauses while the Mac is asleep and resumes after wake.

### Why Safari to Chrome Can Be Slower

Safari does not provide a public bookmark-change notification API. Bookmark Bridge must periodically read and compare Safari's local bookmark file, and Safari may delay writing an edit to disk. Safari-to-Chrome synchronization therefore usually takes a few seconds but can occasionally take tens of seconds. If Chrome's Manifest V3 background extension has been suspended, that can add up to about 30 seconds of waiting. Bookmark Bridge writes only after detecting a real change rather than repeatedly rewriting bookmark data for the sake of lower latency.

## Safety Design

Safari does not expose a public bookmark-writing extension API, so the desktop app reads and writes `~/Library/Safari/Bookmarks.plist` after receiving Full Disk Access. It creates a backup of the original file before every write. The Chrome side uses only the official `chrome.bookmarks` API.

Default backup directory:

```text
~/Library/Application Support/BookmarkBridge/Backups
```

Although the app includes backups and conflict protection, manually exporting bookmarks from both Safari and Chrome before the first synchronization is still recommended.

## Build from Source

Building requires macOS 13 or later, Swift 6, and a macOS SDK.

```bash
swift run BookmarkBridgeChecks
zsh scripts/package-app.sh
```

Generated files:

```text
outputs/Bookmark Bridge.app
outputs/Bookmark Bridge Chrome Extension/
```

Build a universal distribution for Apple silicon and Intel Macs:

```bash
zsh scripts/package-distribution.sh
```

## Project Structure

```text
Sources/BookmarkBridgeCore/   Bookmark model, merging, and Safari storage
Sources/BookmarkBridge/       Menu bar app and local HTTP service
ChromeExtension/              Chrome Manifest V3 extension
Sources/BookmarkBridgeChecks/ Safety checks that do not use real browser data
Distribution/                 Chinese guide included in the release archive
scripts/                      Build and packaging scripts
```

## Privacy

The project contains no telemetry, account system, or cloud service. Safari and Chrome bookmark data is processed only on the local Mac. Do not submit real bookmark files or backups in source code, issues, or logs.

## License

[MIT License](LICENSE)
