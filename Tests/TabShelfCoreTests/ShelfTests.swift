import Foundation
import Testing
@testable import TabShelfCore

final class ShelfTests {
    private var directory: URL!
    private var repository: ShelfRepository!

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("tabshelf-test-\(UUID())")
        repository = ShelfRepository(directory: directory)
    }

    deinit {
        if FileManager.default.fileExists(atPath: directory.path) { try? FileManager.default.removeItem(at: directory) }
    }

    @Test func testNormalizesAddressesWithoutLosingQueryOrFragment() throws {
        #expect(try WebAddress.normalize("  GOOGLE.com  ") == "https://google.com/")
        #expect(try WebAddress.normalize("HTTPS://EXAMPLE.COM:443/a?q=x%20y#section") == "https://example.com/a?q=x%20y#section")
        #expect(try WebAddress.normalize("http://localhost:8080/") == "http://localhost:8080/")
        #expect(try WebAddress.normalize("intranet:8080/path") == "https://intranet:8080/path")
    }

    @Test func testLegacySettingsKeepChromeAndPreservePreferencesWhenSwitching() throws {
        let old = Data(#"{"newTabURL":"https://example.com/","reuseWindow":false}"#.utf8)
        var settings = try JSONDecoder().decode(ShelfSettings.self, from: old)
        #expect(settings.browserDestination == .chrome)
        _ = try repository.add(title: "Keep", url: "keep.example")
        settings.browserDestination = .topChrome
        _ = try repository.saveSettings(settings)
        let reloaded = try ShelfRepository(directory: directory).load()
        #expect(reloaded.settings.browserDestination == .topChrome)
        #expect(reloaded.settings.newTabURL == "https://example.com/")
        #expect(!reloaded.settings.reuseWindow)
        #expect(reloaded.sites.count == 1)
        _ = try repository.add(title: "From extension", url: "new.example")
        #expect(try repository.load().settings.browserDestination == .topChrome)
    }

    @Test func testTopChromeHandoffPreservesNestedURLAndRejectsUnsafeSchemes() throws {
        let address = "https://example.com/a%2Fb?q=a%20b&next=https%3A%2F%2Fother.example%2F#section"
        let link = try TopChromeLink.make(address: address)
        let parts = try #require(URLComponents(url: link, resolvingAgainstBaseURL: false))
        #expect(parts.scheme == "topchrome" && parts.host == "open")
        #expect(parts.queryItems == [URLQueryItem(name: "url", value: address)])
        #expect(parts.fragment == nil)
        #expect(throws: (any Error).self) { try TopChromeLink.make(address: "javascript:alert(1)") }
        #expect(throws: (any Error).self) { try TopChromeLink.make(address: "https://user:password@example.com") }
    }

    @Test func testRejectsUnsafeAndMalformedAddresses() {
        for input in ["", "javascript:alert(1)", "file:///tmp/secret", "chrome://settings", "data:text/html,hello", "https://", "https://a b.com", "https://user:secret@example.com", "https://example.com:99999", "https://example.com/\nattack", "https://example.com/%0Aattack", "https:example.com", "https://example.com\\evil"] {
            #expect(throws: (any Error).self) { try WebAddress.normalize(input) }
        }
    }

    @Test func testPersistsAndDeduplicatesSavedSites() throws {
        let first = try repository.add(title: "Work", url: "EXAMPLE.com")
        #expect(first.inserted)
        let duplicate = try repository.add(title: "Other title", url: "https://example.com/")
        #expect(!(duplicate.inserted))
        let reloaded = try ShelfRepository(directory: directory).load()
        #expect(reloaded.sites.count == 1)
        #expect(reloaded.sites.first?.title == "Work")
        #expect(reloaded.sites.first?.id == first.document.sites.first?.id)
    }

    @Test func testEditRemoveAndPreferencesDoNotDiscardExtensionWrites() throws {
        let first = try repository.add(title: "One", url: "one.example").document.sites[0]
        let secondWriter = ShelfRepository(directory: directory)
        _ = try secondWriter.add(title: "Two", url: "two.example")
        var settings = ShelfSettings()
        settings.newTabURL = "duckduckgo.com"
        settings.reuseWindow = false
        _ = try repository.saveSettings(settings)
        _ = try repository.edit(id: first.id, title: "Renamed", url: "one.example/path")
        let result = try repository.load()
        #expect(result.sites.count == 2)
        #expect(result.settings.newTabURL == "https://duckduckgo.com/")
        #expect(!(result.settings.reuseWindow))
        _ = try repository.remove(id: first.id)
        #expect(try secondWriter.load().sites.map(\.title) == ["Two"])
    }

    @Test func testDuplicateEditCannotReplaceAnotherSite() throws {
        let first = try repository.add(title: "One", url: "one.example").document.sites[0]
        _ = try repository.add(title: "Two", url: "two.example")
        #expect(throws: (any Error).self) { try repository.edit(id: first.id, title: "Oops", url: "two.example") }
        #expect(try repository.load().sites.count == 2)
    }

    @Test func testCorruptFileIsNeverOverwritten() throws {
        _ = try repository.add(title: "One", url: "one.example")
        let invalid = Data("not json".utf8)
        try invalid.write(to: repository.fileURL)
        #expect(throws: (any Error).self) { try repository.add(title: "Two", url: "two.example") }
        #expect(try Data(contentsOf: repository.fileURL) == invalid)
    }

    @Test func testFutureSchemaIsNeverOverwritten() throws {
        _ = try repository.add(title: "One", url: "one.example")
        var document = try repository.load()
        document.version = 3
        let data = try JSONEncoder().encode(document)
        try data.write(to: repository.fileURL)
        #expect(throws: (any Error).self) { try repository.remove(id: document.sites[0].id) }
        #expect(try Data(contentsOf: repository.fileURL) == data)
    }

    @Test func testScriptEscapesURLAndTracksOnlyOwnedTab() throws {
        let script = try ChromeScript.open(url: "https://example.com/?q=\"hello\"", windowID: 12, tabID: 34)
        #expect(script.contains("is 12 then"))
        #expect(script.contains("is 34 then"))
        #expect(!(script.contains("close ")))
        #expect(script.contains("%22hello%22") || script.contains("\\\"hello\\\""))
        #expect(throws: (any Error).self) { try ChromeScript.open(url: "javascript:alert(1)", windowID: nil, tabID: nil) }
    }

    @Test func testTitleFallbackAndLimit() throws {
        #expect(try SavedSite(title: " \n ", url: "https://www.example.com").title == "example.com")
        #expect(try SavedSite(title: String(repeating: "x", count: 300), url: "example.com").title.count == 200)
    }

    @Test func testCurrentChromePagePreservesURLAndCleansMultilineTitle() throws {
        let page = try ChromePage(scriptOutput: "https://example.com/path?q=a%20b#section\nA title, with \"quotes\" 🌎\nand another line\n")
        #expect(page.url == "https://example.com/path?q=a%20b#section")
        #expect(page.title == "A title, with \"quotes\" 🌎 and another line")
        #expect(try ChromePage(scriptOutput: "https://example.com/\n\n").title == "example.com")
    }

    @Test func testCurrentChromePageRejectsUnsupportedPagesAndBrokenResponses() {
        for output in ["", "https://example.com/", "chrome://extensions/\nExtensions", "file:///tmp/test.html\nLocal", "https://user:password@example.com/\nPrivate"] {
            #expect(throws: (any Error).self) { try ChromePage(scriptOutput: output) }
        }
    }

    @Test func testVersionOneMigratesWithoutLosingSitesAndKeepsBackup() throws {
        let originalSite = try SavedSite(title: "Existing", url: "existing.example")
        var original = ShelfDocument()
        original.version = 1
        original.sites = [originalSite]
        original.settings.reuseWindow = false
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json.removeValue(forKey: "groups")
        let oldData = try JSONSerialization.data(withJSONObject: json)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try oldData.write(to: repository.fileURL)
        let loaded = try repository.load()
        #expect(loaded.groups.isEmpty)
        #expect(loaded.sites == [originalSite])
        let migrated = try repository.saveGroup(name: "Work")
        #expect(migrated.version == 2)
        #expect(migrated.sites == [originalSite])
        #expect(!migrated.settings.reuseWindow)
        #expect(try Data(contentsOf: directory.appendingPathComponent("shelf-v1-backup.json")) == oldData)
    }

    @Test func testPinsAndGroupsSurviveExtensionSavesAndReloads() throws {
        let group = try #require(repository.saveGroup(name: "Work").groups.first)
        let first = try repository.add(title: "Pinned", url: "work.example", organization: SiteOrganization(groupID: group.id, isPinned: true)).document.sites[0]
        let pinDate = try #require(first.pinnedAt)
        let extensionWriter = ShelfRepository(directory: directory)
        _ = try extensionWriter.add(title: "Incoming", url: "new.example")
        _ = try extensionWriter.add(title: "Duplicate", url: "work.example")
        let loaded = try repository.load()
        #expect(loaded.groups == [group])
        #expect(loaded.pinnedSites().map(\.id) == [first.id])
        #expect(loaded.pinnedSites().first?.groupID == group.id)
        #expect(loaded.pinnedSites().first?.pinnedAt == pinDate)
        #expect(loaded.pinnedSites().first?.title == "Pinned")
        _ = try repository.setPinned(id: first.id, pinned: false)
        #expect(try extensionWriter.load().pinnedSites().isEmpty)
        #expect(try extensionWriter.load().sites.first(where: { $0.id == first.id })?.groupID == group.id)
    }

    @Test func testRemoveGroupPreservesAllSitesAndPins() throws {
        let group = try #require(repository.saveGroup(name: "Reading").groups.first)
        _ = try repository.add(title: "One", url: "one.example", organization: SiteOrganization(groupID: group.id, isPinned: true))
        _ = try repository.add(title: "Two", url: "two.example", organization: SiteOrganization(groupID: group.id, isPinned: false))
        let before = try repository.load()
        let after = try repository.removeGroup(id: group.id)
        #expect(after.groups.isEmpty)
        #expect(after.sites.map(\.id) == before.sites.map(\.id))
        #expect(after.sites.allSatisfy { $0.groupID == nil })
        #expect(after.pinnedSites().map(\.id) == before.pinnedSites().map(\.id))
    }

    @Test func testGroupValidationAndRenamePreserveMembership() throws {
        let group = try #require(repository.saveGroup(name: "  Work  ").groups.first)
        #expect(group.name == "Work")
        #expect(throws: (any Error).self) { try repository.saveGroup(name: "work") }
        #expect(throws: (any Error).self) { try repository.saveGroup(name: " \n ") }
        #expect(throws: (any Error).self) { try repository.saveGroup(name: String(repeating: "a", count: 61)) }
        let site = try repository.add(title: "One", url: "one.example").document.sites[0]
        _ = try repository.move(id: site.id, to: group.id)
        let renamed = try repository.saveGroup(id: group.id, name: "Projects")
        #expect(renamed.groups.first?.id == group.id)
        #expect(renamed.groups.first?.name == "Projects")
        #expect(renamed.sites.first?.groupID == group.id)
        _ = try repository.move(id: site.id, to: nil)
        #expect(try repository.load().sites.first?.groupID == nil)
    }

    @Test func testMissingGroupCannotPartiallyEditOrLoseSite() throws {
        let site = try repository.add(title: "Keep", url: "keep.example").document.sites[0]
        let before = try Data(contentsOf: repository.fileURL)
        #expect(throws: (any Error).self) {
            try repository.edit(id: site.id, title: "Changed", url: "other.example", organization: SiteOrganization(groupID: UUID(), isPinned: true))
        }
        #expect(throws: (any Error).self) { try repository.move(id: site.id, to: UUID()) }
        #expect(try Data(contentsOf: repository.fileURL) == before)
    }

    @Test func testSearchIncludesGroupsAndPinnedSites() throws {
        let group = try #require(repository.saveGroup(name: "Research").groups.first)
        let pinned = try repository.add(title: "Reference", url: "reference.example", organization: SiteOrganization(groupID: group.id, isPinned: true)).document.sites[0]
        _ = try repository.add(title: "Article", url: "article.example", organization: SiteOrganization(groupID: group.id, isPinned: false))
        _ = try repository.add(title: "Other", url: "other.example")
        let document = try repository.load()
        #expect(document.matchingSites("research").count == 2)
        #expect(document.pinnedSites(matching: "research").map(\.id) == [pinned.id])
        #expect(document.matchingSites("article.example").count == 1)
        #expect(document.matchingSites("missing").isEmpty)
    }
}
