import Foundation

public enum TopChromeLink {
    public static let appID = "local.topchrome.app"

    public static func make(address: String) throws -> URL {
        let address = try WebAddress.normalize(address)
        var components = URLComponents()
        components.scheme = "topchrome"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "url", value: address)]
        guard let url = components.url else { throw ShelfError.invalidURL }
        return url
    }
}
