# TabShelf

[Project website](https://chaosdeselva.github.io/TabShelf/)

A small native Mac menu bar app for the sites you need throughout the day. Save a list, click a site to open it in Chrome, and close the browser window whenever you're finished. Your list stays on the shelf.

## What it does

- Add, search, rename, copy, and remove saved sites. Removal always asks for confirmation.
- Create named groups, move sites between groups, and collapse groups you aren't using.
- Pin favorites to a dedicated section at the top of the list, above every group.
- Choose whether clicks **replace the page in one dedicated Chrome window** or **open a new window each time**.
- In Settings, choose **Open links in → TopChrome** to send saved sites and New Tab to the TopChrome drawer. Choose **Chrome** to use the regular Chrome behavior above. Existing installations keep Chrome selected until you change it.
- Use **New Tab** to open Google, or set your own default address.
- Click **Save Current Chrome Tab** in the shelf to save the active page directly. No extension setup is required, and repeated saves don't create duplicates.
- Optionally use the companion Chrome extension for a toolbar save button.
- Optionally start at login. No Dock icon, account, server, telemetry, or third-party dependencies.

In reuse mode, TabShelf remembers the exact window and tab it created. If that window or tab has closed, it creates another. It doesn't replace a page in your other windows. Extra tabs you open yourself are left alone. Chrome uses its normal profile and existing sign-ins.

Open the updated TopChrome app once before selecting it in TabShelf. TopChrome opens each link as a new drawer tab, preserving existing tabs and revealing a hidden drawer. TabShelf keeps your regular Chrome reuse preference when switching destinations. If TopChrome is unavailable, TabShelf reports it instead of silently opening a different browser. Save Current Chrome Tab works from the drawer too, since it is a real Chrome window.

## Build and install

Requires macOS 13 or later, Google Chrome, and Apple command-line tools with Swift 6 or newer. The build targets the Mac's current architecture.

```sh
./scripts/install.sh
```

This builds and locally signs the app, installs it in `~/Applications/TabShelf.app`, and registers the Chrome save connection for your macOS user. Click the **stacked-rectangles icon near the clock** in the top-right Mac menu bar to open the shelf. Hovering over it identifies it as TabShelf.

The shelf is a native panel anchored below its menu-bar icon. It stays available across normal desktop Spaces. The **Open in Chrome / TopChrome** menu above the site list saves your choice immediately. The gear button, or right-clicking the menu-bar icon, opens Settings. Reopening TabShelf from Finder shows the shelf. Hold ⌘ and drag the menu-bar icon to choose its position.

For subsequent updates, quit TabShelf from its menu before running the installer. Your saved sites and settings are preserved. This is a local development build, not a notarized distribution build.

To build without installing:

```sh
./scripts/build.sh
open dist/TabShelf.app
```

When opening a site for the first time, macOS may ask to let TabShelf control Google Chrome. Allow this to enable window reuse. If declined, enable TabShelf under **System Settings → Privacy & Security → Automation**.

## Set up the Chrome extension

This is optional. The shelf's **Save Current Chrome Tab** button uses the same macOS Chrome-control permission as opening saved sites. It reads only the URL and title of Chrome's active tab when you click it. It does not navigate, close, or reorder your browser windows. Open a normal website first; Chrome settings, new-tab pages, and local files are not supported.

1. Open TabShelf's gear button, then click **Show Extension Folder**. This also installs or repairs the app connection.
2. Open `chrome://extensions` in Chrome and enable **Developer mode**.
3. Click **Load unpacked**, selecting `~/Library/Application Support/TabShelf/ChromeExtension`.
4. Pin **Save to TabShelf** from Chrome's extensions menu.
5. On a website, click the extension. A checkmark means the page was saved; hover over an exclamation badge for an error explanation.

The extension uses `activeTab` to read a page's URL and title when clicked and `nativeMessaging` to save them locally. It doesn't request access to all websites or read page content. Chrome's built-in pages, `file:` URLs, and URLs containing credentials aren't supported. The bridge and app share the same atomic, locked data store; simultaneous saves can't overwrite one another.

If your work Chrome policy blocks unpacked extensions or native messaging, you can still add URLs directly in the menu bar app. The connection currently targets the standard Google Chrome profile directory, not Chromium, Chrome Beta, or a custom `--user-data-dir`.

## Data and behavior

Use **New Group** at the bottom of the shelf to create a group. Choose a group when adding or editing a site, or right-click a site and use **Move to Group**. The pin button on each row pins or unpins that site. A group's **…** menu lets you add a site, rename the group, or remove it. Removing a group keeps its sites in Ungrouped and preserves pins. Searching also matches group names.

Groups organize saved links within TabShelf; they don't create Chrome tab groups. Pages still follow your replace-page or new-window preference.

Saved sites and preferences are in `~/Library/Application Support/TabShelf/shelf.json`. The **More → Show Saved Data** command reveals this folder. Back up that file to preserve your list. A damaged or newer-format file produces an error instead of being replaced with an empty shelf.

The first change to an older shelf upgrades it for groups and pins and saves the original as `shelf-v1-backup.json`. New saves from the extension go into Ungrouped; saving an existing URL preserves its group, custom name, and pin.

Closing a Chrome window doesn't remove a saved site. On macOS, closing the last window can leave Chrome running; use **⌘Q in Chrome** when you want it to quit completely. TabShelf stays in your menu bar and launches Chrome again when needed. It doesn't preload websites or run Chrome in the background itself.

Window reuse survives restarting TabShelf while the same Chrome process remains open. After restarting Chrome, TabShelf creates a fresh dedicated window. Restored Chrome windows are left alone. Switching to new-window mode leaves existing windows open.

To uninstall, turn off start at login, quit TabShelf, remove the Chrome extension, and move `~/Applications/TabShelf.app` to Trash. Remove `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/local.tabshelf.bridge.json` to unregister the bridge. Keep or delete the TabShelf data folder as you prefer.

## Development and verification

```sh
./scripts/test.sh
```

The suite covers URL validation, persistence, duplicates, edits, removals, groups, pinning, schema migration and backups, preference isolation, corrupted files, future schemas, AppleScript escaping, extension success/failure states, native-message framing, and concurrent saves from separate processes. It uses Swift Testing, Node's built-in test runner, and Python's standard library.

In a restricted development environment that doesn't allow SwiftPM to create its nested sandbox, run with `TABSHELF_DISABLE_SWIFT_SANDBOX=1`. For isolated data tests, `TABSHELF_DATA_DIR` overrides the storage folder; `TABSHELF_SKIP_APP_LAUNCH=1` prevents bridge tests from opening the app.

Manual UI checks: add a site, restart and reopen it, cancel and confirm removal, change the default URL, switch window behavior, close and recreate the dedicated window, and save twice through the extension. Verify unrelated Chrome windows remain unchanged.

For groups and pins: create and rename a group, move a site into it, pin that site, and check it appears once in Pinned with its group name. Unpin it and confirm it returns to its group. Search by group name, collapse and reopen a group, cancel group removal, then remove the group and confirm its sites remain in Ungrouped. Save a grouped, pinned URL from Chrome again and verify its organization stays intact.

Implementation references: [Chrome native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging), [activeTab](https://developer.chrome.com/docs/extensions/develop/concepts/activeTab), and [stable extension IDs](https://developer.chrome.com/docs/extensions/reference/manifest/key).

The open shelf stays visible across normal desktop Spaces. Click its menu-bar icon or press Escape to hide it; opening a site also hides the shelf.
