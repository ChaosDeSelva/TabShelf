const { test } = require("node:test");
const assert = require("node:assert/strict");
const { readFileSync } = require("node:fs");
const vm = require("node:vm");
const source = readFileSync("extension/background.js", "utf8");

function extension(reply) {
  let click;
  const calls = [];
  const chrome = {
    action: {
      onClicked: { addListener(handler) { click = handler; } },
      ...Object.fromEntries(["setBadgeText", "setBadgeBackgroundColor", "setTitle"].map((name) => [name, async (value) => { calls.push([name, value]); }])),
    },
    runtime: { async sendNativeMessage(host, payload) { calls.push(["send", host, payload]); return reply(); } },
  };
  vm.runInNewContext(source, { chrome });
  return { calls, click };
}

test("explicit toolbar click saves the active page and shows success", async () => {
  const { click, calls } = extension(() => ({ ok: true, inserted: true }));
  await click({ id: 7, url: "https://example.com/", title: "Example" });
  assert.equal(calls.find(([kind]) => kind === "send")[2].url, "https://example.com/");
  assert.equal(calls.at(-1)[1].title, "Saved to TabShelf");
});

test("internal URLs never reach the native host", async () => {
  const { click, calls } = extension(() => { throw new Error("must not run"); });
  await click({ id: 7, url: "chrome://settings" });
  assert.equal(calls.some(([kind]) => kind === "send"), false);
  assert.match(calls.at(-1)[1].title, /regular website/);
});

test("missing native host gives actionable setup instructions", async () => {
  const { click, calls } = extension(() => { throw new Error("Specified native messaging host not found."); });
  await click({ id: 7, url: "https://example.com/" });
  assert.match(calls.at(-1)[1].title, /Show Extension Folder/);
});

test("save failure is not reported as success", async () => {
  const { click, calls } = extension(() => ({ ok: false, error: "Disk full" }));
  await click({ id: 7, url: "https://example.com/" });
  assert.equal(calls.at(-1)[1].title, "Disk full");
  assert.equal(calls.some(([kind, value]) => kind === "setBadgeText" && value.text === "✓"), false);
});

test("duplicates are clearly acknowledged", async () => {
  const { click, calls } = extension(() => ({ ok: true, inserted: false }));
  await click({ id: 7, url: "https://example.com/" });
  assert.equal(calls.at(-1)[1].title, "Already saved to TabShelf");
});
