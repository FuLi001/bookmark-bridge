const SERVER = "http://127.0.0.1:17315";
let applyingCommand = false;
let sendTimer = null;
let commandLoopActive = false;

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

async function getBookmarkBar() {
  const tree = await chrome.bookmarks.getTree();
  const root = tree[0];
  const bookmarkBar = (root.children || []).find(node => node.id === "1")
    || (root.children || []).find(node => /bookmark.?bar|书签栏/i.test(node.title));
  if (!bookmarkBar) throw new Error("找不到 Chrome 书签栏");
  return bookmarkBar;
}

async function sendSnapshot() {
  if (applyingCommand) return;
  try {
    const bookmarkBar = await getBookmarkBar();
    await fetch(`${SERVER}/chrome/snapshot`, {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({tree: normalizeNode(bookmarkBar, true)})
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
    const response = await fetch(`${SERVER}/chrome/commands`, {cache: "no-store"});
    if (response.status === 204) return true;
    if (!response.ok) throw new Error(`本地服务返回 ${response.status}`);

    const command = await response.json();
    applyingCommand = true;
    try {
      const bookmarkBar = await getBookmarkBar();
      await reconcileChildren(bookmarkBar.id, command.tree.children || []);
      await fetch(`${SERVER}/chrome/ack`, {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({revision: command.revision, success: true})
      });
      await sendSnapshot();
    } catch (error) {
      await fetch(`${SERVER}/chrome/ack`, {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({revision: command.revision, success: false, message: String(error)})
      });
    } finally {
      applyingCommand = false;
    }
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
