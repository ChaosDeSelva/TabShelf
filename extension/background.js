const HOST = "local.tabshelf.bridge";

chrome.action.onClicked.addListener(async (tab) => {
  if (typeof tab.id !== "number") return;
  const tabId = tab.id;
  try {
    if (!tab.url || !/^https?:\/\//i.test(tab.url)) {
      throw new Error("Open a regular website first. Chrome's internal pages can't be saved.");
    }
    await chrome.action.setBadgeText({ tabId, text: "…" });
    const response = await chrome.runtime.sendNativeMessage(HOST, {
      type: "save",
      url: tab.url,
      title: tab.title || "",
    });
    if (!response?.ok) throw new Error(response?.error || "TabShelf couldn't save this page.");
    await chrome.action.setBadgeBackgroundColor({ tabId, color: "#4A5CDC" });
    await chrome.action.setBadgeText({ tabId, text: "✓" });
    await chrome.action.setTitle({
      tabId,
      title: response.inserted ? "Saved to TabShelf" : "Already saved to TabShelf",
    });
  } catch (error) {
    let message = error.message || String(error);
    if (/native messaging host|native host|specified native/i.test(message)) {
      message = "Open TabShelf Settings → Show Extension Folder to connect the app, then try again.";
    }
    // The tab can close while the native host is saving; don't turn that into an unhandled rejection.
    await Promise.allSettled([
      chrome.action.setBadgeBackgroundColor({ tabId, color: "#C74545" }),
      chrome.action.setBadgeText({ tabId, text: "!" }),
      chrome.action.setTitle({ tabId, title: message }),
    ]);
  }
});
