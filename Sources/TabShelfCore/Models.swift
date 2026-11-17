import Foundation

public enum ShelfError: LocalizedError {
    case invalidURL, duplicateURL, missingItem, unsupportedVersion, invalidMessage, invalidGroupName, duplicateGroupName, missingGroup

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Enter a valid http or https address, such as google.com. Passwords in URLs are not supported."
        case .duplicateURL: return "That address is already on your shelf."
        case .missingItem: return "This site was removed. Reopen the shelf and try again."
        case .unsupportedVersion: return "This shelf was saved by a newer version of TabShelf. Update the app before editing it."
        case .invalidMessage: return "The extension sent an invalid message."
        case .invalidGroupName: return "Enter a group name between 1 and 60 characters."
        case .duplicateGroupName: return "A group with that name already exists."
        case .missingGroup: return "This group was removed. Choose another group and try again."
        }
    }
}

public enum WebAddress {
    public static func normalize(_ input: String) throws -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 16_384,
              !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              !text.contains("\\") else { throw ShelfError.invalidURL }
        if !text.contains("://") {
            if let colon = text.firstIndex(of: ":") {
                let suffix = text[text.index(after: colon)...].prefix(while: { $0 != "/" && $0 != "?" && $0 != "#" })
                guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber) else { throw ShelfError.invalidURL }
            }
            text = "https://" + text
        }
        guard var components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              !host.contains(where: { $0.isWhitespace }),
              components.user == nil, components.password == nil,
              components.port.map({ (1...65535).contains($0) }) ?? true else { throw ShelfError.invalidURL }
        components.scheme = scheme
        components.host = host.lowercased()
        if (scheme == "https" && components.port == 443) || (scheme == "http" && components.port == 80) {
            components.port = nil
        }
        if components.path.isEmpty { components.path = "/" }
        guard let url = components.url, let result = url.absoluteString.removingPercentEncoding,
              !result.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ShelfError.invalidURL
        }
        return url.absoluteString
    }

    public static func displayHost(_ address: String) -> String {
        let host = URLComponents(string: address)?.host ?? address
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

public struct SavedSite: Codable, Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public var url: String
    public let createdAt: Date
    public var groupID: UUID?
    public var pinnedAt: Date?
    public var isPinned: Bool { pinnedAt != nil }

    public init(id: UUID = UUID(), title: String, url: String, createdAt: Date = Date()) throws {
        self.id = id
        self.url = try WebAddress.normalize(url)
        self.title = Self.cleanTitle(title, url: self.url)
        self.createdAt = createdAt
    }

    public static func cleanTitle(_ title: String, url: String) -> String {
        let clean = title.components(separatedBy: .controlCharacters).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? WebAddress.displayHost(url) : String(clean.prefix(200))
    }
}

public struct SiteOrganization {
    public var groupID: UUID?
    public var isPinned: Bool
    public init(groupID: UUID?, isPinned: Bool) { self.groupID = groupID; self.isPinned = isPinned }
}

public struct SiteGroup: Codable, Identifiable, Equatable {
    public let id: UUID
    public var name: String

    public init(id: UUID = UUID(), name: String) throws {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.count <= 60,
              !clean.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw ShelfError.invalidGroupName
        }
        self.id = id
        self.name = clean
    }
}

public enum BrowserDestination: String, Codable, CaseIterable {
    case chrome, topChrome
}

public struct ShelfSettings: Codable, Equatable {
    public var newTabURL = "https://www.google.com/"
    public var reuseWindow = true
    public var browserDestination = BrowserDestination.chrome
    public init() {}

    private enum CodingKeys: String, CodingKey { case newTabURL, reuseWindow, browserDestination }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        newTabURL = try values.decode(String.self, forKey: .newTabURL)
        reuseWindow = try values.decode(Bool.self, forKey: .reuseWindow)
        browserDestination = try values.decodeIfPresent(BrowserDestination.self, forKey: .browserDestination) ?? .chrome
    }
}

public struct ShelfDocument: Codable, Equatable {
    public var version = 2
    public var sites: [SavedSite] = []
    public var groups: [SiteGroup] = []
    public var settings = ShelfSettings()
    public init() {}

    private enum CodingKeys: String, CodingKey { case version, sites, groups, settings }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        sites = try values.decode([SavedSite].self, forKey: .sites)
        groups = try values.decodeIfPresent([SiteGroup].self, forKey: .groups) ?? []
        settings = try values.decode(ShelfSettings.self, forKey: .settings)
    }

    public func matchingSites(_ query: String) -> [SavedSite] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return sites }
        let matchingGroups = Set(groups.filter { $0.name.localizedCaseInsensitiveContains(query) }.map(\.id))
        return sites.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.url.localizedCaseInsensitiveContains(query)
                || $0.groupID.map { matchingGroups.contains($0) } == true
        }
    }

    public func pinnedSites(matching query: String = "") -> [SavedSite] {
        matchingSites(query).filter(\.isPinned).sorted {
            if $0.pinnedAt == $1.pinnedAt { return $0.id.uuidString < $1.id.uuidString }
            return ($0.pinnedAt ?? .distantPast) > ($1.pinnedAt ?? .distantPast)
        }
    }
}

public enum TabShelfPaths {
    public static let appID = "local.tabshelf.app"
    public static let hostName = "local.tabshelf.bridge"
    public static let extensionID = "dmapmjjnmecefkegcdlglnncnfjnnddp"
    public static let changedNotification = "local.tabshelf.changed"

    public static var dataDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["TABSHELF_DATA_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TabShelf", isDirectory: true)
    }
}
