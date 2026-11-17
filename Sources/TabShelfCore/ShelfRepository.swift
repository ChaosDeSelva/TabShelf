import Darwin
import Foundation

public final class ShelfRepository {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("shelf.json") }

    public init(directory: URL = TabShelfPaths.dataDirectory) { self.directory = directory }

    public func load() throws -> ShelfDocument {
        try withLock { try read() }
    }

    @discardableResult
    public func add(title: String, url: String, organization: SiteOrganization? = nil) throws -> (document: ShelfDocument, inserted: Bool) {
        var site = try SavedSite(title: title, url: url)
        var inserted = false
        let document = try mutate { document in
            guard !document.sites.contains(where: { $0.url == site.url }) else { return }
            if let organization {
                try validateGroup(organization.groupID, in: document)
                site.groupID = organization.groupID
                site.pinnedAt = organization.isPinned ? Date() : nil
            }
            document.sites.insert(site, at: 0)
            inserted = true
        }
        return (document, inserted)
    }

    @discardableResult
    public func edit(id: UUID, title: String, url: String, organization: SiteOrganization? = nil) throws -> ShelfDocument {
        let normalized = try WebAddress.normalize(url)
        return try mutate { document in
            guard let index = document.sites.firstIndex(where: { $0.id == id }) else { throw ShelfError.missingItem }
            guard !document.sites.contains(where: { $0.id != id && $0.url == normalized }) else { throw ShelfError.duplicateURL }
            if let organization {
                try validateGroup(organization.groupID, in: document)
                document.sites[index].groupID = organization.groupID
                document.sites[index].pinnedAt = organization.isPinned ? (document.sites[index].pinnedAt ?? Date()) : nil
            }
            document.sites[index].title = SavedSite.cleanTitle(title, url: normalized)
            document.sites[index].url = normalized
        }
    }

    @discardableResult
    public func remove(id: UUID) throws -> ShelfDocument {
        try mutate { $0.sites.removeAll(where: { $0.id == id }) }
    }

    @discardableResult
    public func setPinned(id: UUID, pinned: Bool) throws -> ShelfDocument {
        try mutate { document in
            guard let index = document.sites.firstIndex(where: { $0.id == id }) else { throw ShelfError.missingItem }
            document.sites[index].pinnedAt = pinned ? (document.sites[index].pinnedAt ?? Date()) : nil
        }
    }

    @discardableResult
    public func move(id: UUID, to groupID: UUID?) throws -> ShelfDocument {
        try mutate { document in
            guard let index = document.sites.firstIndex(where: { $0.id == id }) else { throw ShelfError.missingItem }
            try validateGroup(groupID, in: document)
            document.sites[index].groupID = groupID
        }
    }

    @discardableResult
    public func saveGroup(id: UUID? = nil, name: String) throws -> ShelfDocument {
        let group = try SiteGroup(id: id ?? UUID(), name: name)
        return try mutate { document in
            guard !document.groups.contains(where: { $0.id != group.id && $0.name.localizedCaseInsensitiveCompare(group.name) == .orderedSame }) else {
                throw ShelfError.duplicateGroupName
            }
            if let id {
                guard let index = document.groups.firstIndex(where: { $0.id == id }) else { throw ShelfError.missingGroup }
                document.groups[index] = group
            } else { document.groups.append(group) }
        }
    }

    @discardableResult
    public func removeGroup(id: UUID) throws -> ShelfDocument {
        try mutate { document in
            document.groups.removeAll { $0.id == id }
            for index in document.sites.indices where document.sites[index].groupID == id {
                document.sites[index].groupID = nil
            }
        }
    }

    private func validateGroup(_ id: UUID?, in document: ShelfDocument) throws {
        if let id, !document.groups.contains(where: { $0.id == id }) { throw ShelfError.missingGroup }
    }

    @discardableResult
    public func saveSettings(_ settings: ShelfSettings) throws -> ShelfDocument {
        var normalized = settings
        normalized.newTabURL = try WebAddress.normalize(settings.newTabURL)
        return try mutate { $0.settings = normalized }
    }

    private func mutate(_ change: (inout ShelfDocument) throws -> Void) throws -> ShelfDocument {
        try withLock {
            var document = try read()
            let previousVersion = document.version
            try change(&document)
            if previousVersion == 1 {
                let backup = directory.appendingPathComponent("shelf-v1-backup.json")
                if !FileManager.default.fileExists(atPath: backup.path) {
                    try Data(contentsOf: fileURL).write(to: backup, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
                }
            }
            document.version = 2
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let data = try encoder.encode(document)
            try data.write(to: fileURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            return document
        }
    }

    private func read() throws -> ShelfDocument {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return ShelfDocument() }
        let document = try JSONDecoder().decode(ShelfDocument.self, from: Data(contentsOf: fileURL))
        guard (1...2).contains(document.version) else { throw ShelfError.unsupportedVersion }
        _ = try WebAddress.normalize(document.settings.newTabURL)
        for site in document.sites { _ = try WebAddress.normalize(site.url) }
        return document
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let descriptor = open(directory.appendingPathComponent("shelf.lock").path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        // Lock the stable sidecar: atomic replacement changes shelf.json's inode.
        guard flock(descriptor, LOCK_EX) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { flock(descriptor, LOCK_UN) }
        return try body()
    }
}
