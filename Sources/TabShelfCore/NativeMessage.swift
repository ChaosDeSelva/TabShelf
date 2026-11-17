import Foundation

public struct SaveMessage: Codable {
    public let type: String
    public let url: String
    public let title: String?
}

public enum NativeMessage {
    public static func read(from handle: FileHandle) throws -> SaveMessage {
        let header = try readExactly(4, from: handle)
        let size = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        guard size > 0, size <= 128 * 1024 else { throw ShelfError.invalidMessage }
        let body = try readExactly(Int(size), from: handle)
        let message = try JSONDecoder().decode(SaveMessage.self, from: body)
        guard message.type == "save" else { throw ShelfError.invalidMessage }
        return message
    }

    public static func write(_ response: [String: Any], to handle: FileHandle) throws {
        let data = try JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
        var size = UInt32(data.count)
        let header = withUnsafeBytes(of: &size) { Data($0) }
        try handle.write(contentsOf: header + data)
    }

    private static func readExactly(_ count: Int, from handle: FileHandle) throws -> Data {
        var result = Data()
        while result.count < count {
            guard let chunk = try handle.read(upToCount: count - result.count), !chunk.isEmpty else {
                throw ShelfError.invalidMessage
            }
            result.append(chunk)
        }
        return result
    }
}
