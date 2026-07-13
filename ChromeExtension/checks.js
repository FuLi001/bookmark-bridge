const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

let source = fs.readFileSync(path.join(__dirname, "background.js"), "utf8");
source = source.replace(/\nsendSnapshot\(\);\nstartCommandLoop\(\);\s*$/, "");

const bookmarkTree = [{
  id: "0",
  title: "",
  children: [
    {
      id: "1",
      title: "书签栏",
      children: [{id: "10", title: "工作", children: []}]
    },
    {
      id: "2",
      title: "其他书签",
      children: [{id: "20", title: "稍后阅读", children: []}]
    },
    {
      id: "managed",
      title: "受管理书签",
      unmodifiable: "managed",
      children: []
    }
  ]
}];

const noOpEvent = {addListener() {}};
const context = {
  chrome: {
    action: {setBadgeText: async () => {}, setBadgeBackgroundColor: async () => {}, onClicked: noOpEvent},
    alarms: {create() {}, onAlarm: noOpEvent},
    bookmarks: {
      getTree: async () => bookmarkTree,
      getSubTree: async id => {
        const find = node => node.id === id ? node : (node.children || []).map(find).find(Boolean);
        return [find(bookmarkTree[0])].filter(Boolean);
      },
      onCreated: noOpEvent,
      onRemoved: noOpEvent,
      onChanged: noOpEvent,
      onMoved: noOpEvent,
      onChildrenReordered: noOpEvent
    },
    runtime: {onInstalled: noOpEvent, onStartup: noOpEvent}
  },
  clearTimeout,
  console,
  fetch: async () => { throw new Error("Unexpected network request in checks"); },
  setTimeout
};

vm.createContext(context);
vm.runInContext(source, context, {filename: "background.js"});

(async () => {
  const choices = context.collectFolderChoices(bookmarkTree[0], [], true);
  assert.deepStrictEqual(
    JSON.parse(JSON.stringify(choices)),
    [
      {id: "chrome:bookmark-bar", title: "书签栏", path: ["书签栏"]},
      {id: "10", title: "工作", path: ["书签栏", "工作"]},
      {id: "2", title: "其他书签", path: ["其他书签"]},
      {id: "20", title: "稍后阅读", path: ["其他书签", "稍后阅读"]}
    ]
  );

  const defaultFolder = await context.getSelectedFolder("chrome:bookmark-bar");
  const customFolder = await context.getSelectedFolder("20");
  assert.strictEqual(defaultFolder.id, "1");
  assert.strictEqual(customFolder.title, "稍后阅读");
  console.log("Chrome extension checks passed");
})().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
