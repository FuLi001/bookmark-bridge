const SERVER = "http://127.0.0.1:17315";
const DEFAULT_CHROME_FOLDER_ID = "chrome:bookmark-bar";
let applyingCommand = false;
let sendTimer = null;
let commandLoopActive = false;
let activeConfiguration = {chromeFolderID: DEFAULT_CHROME_FOLDER_ID, revision: -1};

function normalizeNode(node, isRoot = false) {
  if (node.url !== undefined) {
    return {
      kind: "bookmark",
      title: node.title || node.url,
      url: node.url,
      children: []
    };
  }
  return {
    kind: "folder",
    title: isRoot ? "root" : (node.title || "未命名文件夹"),
    children: (node.children || []).map(child => normalizeNode(child))
  };
}

function findBookmarkBar(root) {
  const bookmarkBar = (root.children || []).find(node => node.id === "1")
    || (root.children || []).find(node => /bookmark.?bar|书签栏/i.test(node.title));
  if (!bookmarkBar) throw new Error("找不到 Chrome 书签栏");
  return bookmarkBar;
}

async function getSelectedFolder(folderID) {
  if (folderID === DEFAULT_CHROME_FOLDER_ID) {
    const tree = await chrome.bookmarks.getTree();
    return findBookmarkBar(tree[0]);
  }
  const subtree = await chrome.bookmarks.getSubTree(folderID);
  const folder = subtree[0];
  if (!folder || folder.url !== undefined) throw new Error("找不到所选 Chrome 书签目录");
  return folder;
}

function collectFolderChoices(node, parentPath = [], isBrowserRoot = false) {
  const result = [];
  for (const child of node.children || []) {
    if (child.url !== undefined || child.unmodifiable) continue;
    const path = isBrowserRoot ? [child.title] : [...parentPath, child.title];
    const isBookmarkBar = isBrowserRoot && (child.id === "1" || /bookmark.?bar|书签栏/i.test(child.title));
    result.push({
      id: isBookmarkBar ? DEFAULT_CHROME_FOLDER_ID : child.id,
      title: child.title || "未命名文件夹",
      path
    });
    result.push(...collectFolderChoices(child, path));
  }
  return result;
}

async function fetchConfiguration() {
  const response = await fetch(`${SERVER}/configuration`, {cache: "no-store"});
  if (!response.ok) throw new Error(`本地服务返回 ${response.status}`);
  return response.json();
}

async function refreshConfiguration() {
  const configuration = await fetchConfiguration();
  const changed = configuration.revision !== activeConfiguration.revision
    || configuration.chromeFolderID !== activeConfiguration.chromeFolderID;
  activeConfiguration = configuration;
  return changed;
}

async function sendSnapshot() {
  if (applyingCommand) return;
  try {
    await refreshConfiguration();
    const fullTree = await chrome.bookmarks.getTree();
    const folders = collectFolderChoices(fullTree[0], [], true);
    let selectedFolder;
    try {
      selectedFolder = await getSelectedFolder(activeConfiguration.chromeFolderID);
    } catch (_) {
      await fetch(`${SERVER}/chrome/folder-error`, {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({
          folderID: activeConfiguration.chromeFolderID,
          message: "找不到所选 Chrome 同步目录，自动同步已暂停",
          folders
        })
      });
      throw new Error("找不到所选 Chrome 同步目录");
    }
    const selectedChoice = folders.find(folder => folder.id === activeConfiguration.chromeFolderID);
    await fetch(`${SERVER}/chrome/snapshot`, {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({
        tree: normalizeNode(selectedFolder, true),
        folderID: activeConfiguration.chromeFolderID,
        folderPath: (selectedChoice?.path || [selectedFolder.title]).join(" › "),
        folders
      })
    });
    await chrome.action.setBadgeText({text: ""});
  } catch (error) {
    await chrome.action.setBadgeBackgroundColor({color: "#D97706"});
    await chrome.action.setBadgeText({text: "!"});
  }
}

function scheduleSnapshot() {
  clearTimeout(sendTimer);
  sendTimer = setTimeout(sendSnapshot, 500);
}

function nodeMatches(existing, desired) {
  if (desired.kind === "folder") return existing.url === undefined && existing.title === desired.title;
  return existing.url === desired.url;
}

async function reconcileChildren(parentId, desiredChildren) {
  let existingChildren = await chrome.bookmarks.getChildren(parentId);
  const used = new Set();

  for (let index = 0; index < desiredChildren.length; index += 1) {
    const desired = desiredChildren[index];
    let existing = existingChildren.find(node => !used.has(node.id) && nodeMatches(node, desired));

    if (!existing) {
      existing = await chrome.bookmarks.create({
        parentId,
        index,
        title: desired.title,
        ...(desired.kind === "bookmark" ? {url: desired.url} : {})
      });
      existingChildren.push(existing);
    } else {
      const update = {};
      if (existing.title !== desired.title) update.title = desired.title;
      if (desired.kind === "bookmark" && existing.url !== desired.url) update.url = desired.url;
      if (Object.keys(update).length > 0) existing = await chrome.bookmarks.update(existing.id, update);
      if (existing.index !== index || existing.parentId !== parentId) {
        existing = await chrome.bookmarks.move(existing.id, {parentId, index});
      }
    }

    used.add(existing.id);
    if (desired.kind === "folder") {
      await reconcileChildren(existing.id, desired.children || []);
    }
  }

  existingChildren = await chrome.bookmarks.getChildren(parentId);
  for (const extra of existingChildren) {
    if (!used.has(extra.id)) {
      await chrome.bookmarks.removeTree(extra.id);
    }
  }
}

async function pollCommands() {
  try {
    const configurationChanged = await refreshConfiguration();
    if (configurationChanged) await sendSnapshot();
    const response = await fetch(`${SERVER}/chrome/commands`, {cache: "no-store"});
    if (response.status === 204) return true;
    if (!response.ok) throw new Error(`本地服务返回 ${response.status}`);

    const command = await response.json();
    applyingCommand = true;
    let commandSucceeded = false;
    try {
      const targetFolder = await getSelectedFolder(command.folderID || activeConfiguration.chromeFolderID);
      await reconcileChildren(targetFolder.id, command.tree.children || []);
      await fetch(`${SERVER}/chrome/ack`, {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({revision: command.revision, success: true})
      });
      commandSucceeded = true;
    } catch (error) {
      await fetch(`${SERVER}/chrome/ack`, {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({revision: command.revision, success: false, message: String(error)})
      });
    } finally {
      applyingCommand = false;
    }
    if (commandSucceeded) await sendSnapshot();
    return true;
  } catch (_) {
    // The menu bar app may not be running yet.
    return false;
  }
}

function delay(milliseconds) {
  return new Promise(resolve => setTimeout(resolve, milliseconds));
}

async function startCommandLoop() {
  if (commandLoopActive) return;
  commandLoopActive = true;
  while (true) {
    const connected = await pollCommands();
    if (!connected) await delay(2000);
  }
}

chrome.bookmarks.onCreated.addListener(scheduleSnapshot);
chrome.bookmarks.onRemoved.addListener(scheduleSnapshot);
chrome.bookmarks.onChanged.addListener(scheduleSnapshot);
chrome.bookmarks.onMoved.addListener(scheduleSnapshot);
chrome.bookmarks.onChildrenReordered.addListener(scheduleSnapshot);

chrome.runtime.onInstalled.addListener(() => {
  chrome.alarms.create("bookmark-bridge", {periodInMinutes: 0.5});
  sendSnapshot();
  startCommandLoop();
});
chrome.runtime.onStartup.addListener(() => {
  sendSnapshot();
  startCommandLoop();
});
chrome.alarms.onAlarm.addListener(alarm => {
  if (alarm.name === "bookmark-bridge") {
    sendSnapshot();
    startCommandLoop();
  }
});

chrome.action.onClicked.addListener(async () => {
  await sendSnapshot();
  startCommandLoop();
});

sendSnapshot();
startCommandLoop();
