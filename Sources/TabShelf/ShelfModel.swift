import AppKit
import SwiftUI
import TabShelfCore

final class ShelfModel: ObservableObject {
    @Published private(set) var document = ShelfDocument()
    @Published var error: String?
    @Published var notice: String?
    @Published var opening = false
    @Published var savingChromePage = false
    private let repository = ShelfRepository()
    private let launcher = ChromeLauncher()
    var closePopover: (() -> Void)?

    init() { reload() }

    func saveCurrentChromePage() {
        guard !savingChromePage else { return }
        savingChromePage = true
        error = nil
        launcher.currentPage { result in
            self.savingChromePage = false
            do {
                let page = try result.get()
                let saved = try self.repository.add(title: page.title, url: page.url)
                self.document = saved.document
                self.notice = saved.inserted ? "Saved from Chrome" : "Already on your shelf"
            } catch { self.error = error.localizedDescription }
        }
    }

    func reload() {
        do {
            document = try repository.load()
            error = nil
        } catch {
            self.error = "Couldn't read your shelf. Your saved file has been left intact. \(error.localizedDescription)"
        }
    }

    func save(id: UUID?, title: String, url: String, groupID: UUID?, pinned: Bool) throws {
        let organization = SiteOrganization(groupID: groupID, isPinned: pinned)
        if let id {
            document = try repository.edit(id: id, title: title, url: url, organization: organization)
            notice = "Site updated"
        } else {
            let result = try repository.add(title: title, url: url, organization: organization)
            document = result.document
            notice = result.inserted ? "Saved to your shelf" : "Already on your shelf"
        }
    }

    func togglePin(_ site: SavedSite) {
        do {
            document = try repository.setPinned(id: site.id, pinned: !site.isPinned)
            notice = site.isPinned ? "Unpinned" : "Pinned to the top"
        } catch { self.error = error.localizedDescription }
    }

    func move(_ site: SavedSite, to groupID: UUID?) {
        do {
            document = try repository.move(id: site.id, to: groupID)
            notice = "Site moved"
        } catch { self.error = error.localizedDescription }
    }

    func saveGroup(id: UUID?, name: String) throws {
        document = try repository.saveGroup(id: id, name: name)
        notice = id == nil ? "Group created" : "Group renamed"
    }

    func removeGroup(_ group: SiteGroup) {
        do {
            document = try repository.removeGroup(id: group.id)
            notice = "Group removed. Sites kept."
        } catch { self.error = error.localizedDescription }
    }

    func remove(_ site: SavedSite) {
        do {
            document = try repository.remove(id: site.id)
            notice = "Removed from your shelf"
        } catch { self.error = error.localizedDescription }
    }

    func saveSettings(_ settings: ShelfSettings) throws {
        document = try repository.saveSettings(settings)
    }

    func setBrowserDestination(_ destination: BrowserDestination) {
        do {
            var settings = document.settings
            settings.browserDestination = destination
            try saveSettings(settings)
            notice = destination == .topChrome ? "Links now open in TopChrome" : "Links now open in Chrome"
        } catch { self.error = error.localizedDescription }
    }

    func open(_ url: String) {
        guard !opening else { return }
        opening = true
        closePopover?()
        launcher.open(url, destination: document.settings.browserDestination, reuse: document.settings.reuseWindow) { result in
            self.opening = false
            if case .failure(let error) = result {
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = "Couldn't open the page"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }
}
