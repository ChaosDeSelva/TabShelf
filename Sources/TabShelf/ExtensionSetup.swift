import AppKit
import TabShelfCore

enum ExtensionSetup {
    static var extensionDirectory: URL { TabShelfPaths.dataDirectory.appendingPathComponent("ChromeExtension") }

    static func install() throws {
        guard let resources = Bundle.main.resourceURL else { throw LaunchError.message("Reinstall TabShelf to set up the extension.") }
        let bridge = resources.appendingPathComponent("TabShelfBridge")
        let source = resources.appendingPathComponent("extension")
        let manager = FileManager.default
        guard manager.isExecutableFile(atPath: bridge.path), manager.fileExists(atPath: source.path) else {
            throw LaunchError.message("The extension files are missing. Run scripts/install.sh from the project to install the full app.")
        }
        try manager.createDirectory(at: extensionDirectory, withIntermediateDirectories: true)
        for file in try manager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            let target = extensionDirectory.appendingPathComponent(file.lastPathComponent)
            let contents = try Data(contentsOf: file)
            try contents.write(to: target, options: .atomic)
        }
        let hosts = manager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts")
        try manager.createDirectory(at: hosts, withIntermediateDirectories: true)
        let manifest: [String: Any] = [
            "name": TabShelfPaths.hostName,
            "description": "Save pages to TabShelf",
            "path": bridge.path,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(TabShelfPaths.extensionID)/"]
        ]
        try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            .write(to: hosts.appendingPathComponent("\(TabShelfPaths.hostName).json"), options: .atomic)
    }

    static func reveal() throws {
        try install()
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: extensionDirectory.path)
    }
}
