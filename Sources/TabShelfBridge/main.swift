import AppKit
import TabShelfCore

do {
    let origin = CommandLine.arguments.dropFirst().first
    guard origin == "chrome-extension://\(TabShelfPaths.extensionID)/" else { throw ShelfError.invalidMessage }
    let message = try NativeMessage.read(from: .standardInput)
    let result = try ShelfRepository().add(title: message.title ?? "", url: message.url)
    DistributedNotificationCenter.default().postNotificationName(
        NSNotification.Name(TabShelfPaths.changedNotification), object: nil, userInfo: nil, deliverImmediately: true
    )
    if ProcessInfo.processInfo.environment["TABSHELF_SKIP_APP_LAUNCH"] != "1",
       NSRunningApplication.runningApplications(withBundleIdentifier: TabShelfPaths.appID).isEmpty {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let app = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        if app.pathExtension == "app" {
            let launcher = Process()
            launcher.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            launcher.arguments = ["-g", app.path, "--args", "--background"]
            launcher.standardOutput = FileHandle.nullDevice
            launcher.standardError = FileHandle.nullDevice
            if (try? launcher.run()) != nil { launcher.waitUntilExit() }
        }
    }
    try NativeMessage.write(["ok": true, "inserted": result.inserted], to: .standardOutput)
} catch {
    try? NativeMessage.write(["ok": false, "error": error.localizedDescription], to: .standardOutput)
    exit(1)
}
