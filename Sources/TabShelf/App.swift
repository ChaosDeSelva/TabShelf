import AppKit
import SwiftUI
import TabShelfCore

final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 390, height: 640),
                   styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "TabShelf"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
    }

    override func cancelOperation(_ sender: Any?) { orderOut(sender) }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = ShelfModel()
    private let shelfPanel = ShelfPanel()
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem!
    private var observer: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        shelfPanel.contentViewController = NSHostingController(rootView: ShelfView(model: model, showSettings: showSettings))
        model.closePopover = { [weak self] in self?.shelfPanel.orderOut(nil) }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "Item-0"
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "rectangle.stack", accessibilityDescription: "TabShelf")
            button.image?.isTemplate = true
            button.toolTip = "TabShelf · saved sites · right-click for settings"
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        installMenu()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(TabShelfPaths.changedNotification), object: nil, queue: .main
        ) { [weak self] _ in
            self?.model.reload()
            self?.model.notice = "Saved from Chrome"
        }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(desktopChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        do { try ExtensionSetup.install() }
        catch { model.error = error.localizedDescription }
        if !UserDefaults.standard.bool(forKey: "didPresentBrowserDestination") {
            showSettings()
            UserDefaults.standard.set(true, forKey: "didPresentBrowserDestination")
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showShelf()
        return false
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showSettings() }
        else if shelfPanel.isVisible { shelfPanel.orderOut(nil) }
        else { showShelf() }
    }

    @objc private func showShelf() {
        model.reload()
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let anchor = statusItem.button?.window?.frame.maxX ?? visible.maxX
        let height = min(680, visible.height - 16)
        shelfPanel.setFrame(NSRect(x: min(max(visible.minX, anchor - 390), visible.maxX - 390),
                                  y: visible.maxY - height - 6, width: 390, height: height), display: true)
        NSApp.activate(ignoringOtherApps: true)
        shelfPanel.makeKeyAndOrderFront(nil)
    }

    @objc private func desktopChanged() {
        guard shelfPanel.isVisible else { return }
        shelfPanel.orderFrontRegardless()
    }

    @objc func showSettings() {
        shelfPanel.orderOut(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 630),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "TabShelf Settings"
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentViewController = NSHostingController(rootView: SettingsView(model: model))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func installMenu() {
        let main = NSMenu()
        let app = NSMenuItem()
        let menu = NSMenu(title: "TabShelf")
        for (title, action, key) in [("Show Shelf", #selector(showShelf), ""), ("Settings…", #selector(showSettings), ","),
                                      ("Quit TabShelf", #selector(NSApplication.terminate(_:)), "q")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = key == "q" ? NSApp : self
            menu.addItem(item)
        }
        app.submenu = menu
        main.addItem(app)
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        edit.submenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.submenu?.addItem(NSMenuItem(title: title, action: NSSelectorFromString(action), keyEquivalent: key))
        }
        main.addItem(edit)
        NSApp.mainMenu = main
    }
}
