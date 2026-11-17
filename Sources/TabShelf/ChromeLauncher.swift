import AppKit
import TabShelfCore

struct ChromeSession: Codable {
    let processID: Int32
    let launchedAt: Date
    let windowID: Int
    let tabID: Int
}

final class ChromeLauncher {
    private let queue = DispatchQueue(label: "local.tabshelf.chrome")
    private let defaults = UserDefaults.standard

    func currentPage(completion: @escaping (Result<ChromePage, Error>) -> Void) {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").isEmpty else {
            completion(.failure(LaunchError.message("Open a website in Chrome first, then save it here.")))
            return
        }
        queue.async {
            do {
                let process = Process()
                let output = Pipe()
                let errors = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", ChromeScript.currentTab]
                process.standardOutput = output
                process.standardError = errors
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let error = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    if error.contains("-1743") || error.contains("not authorized") {
                        throw LaunchError.message("Allow TabShelf to control Google Chrome in System Settings → Privacy & Security → Automation, then try again.")
                    }
                    throw LaunchError.message("Couldn't read Chrome's current tab. \(error.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
                let page: ChromePage
                do { page = try ChromePage(scriptOutput: String(decoding: data, as: UTF8.self)) }
                catch { throw LaunchError.message("Open a regular http or https website in Chrome first. Chrome's settings, new-tab pages, and local files can't be saved.") }
                DispatchQueue.main.async { completion(.success(page)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    func open(_ address: String, destination: BrowserDestination, reuse: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
        if destination == .topChrome {
            openInTopChrome(address, completion: completion)
            return
        }
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") != nil else {
            completion(.failure(LaunchError.message("Google Chrome isn't installed. Install it in Applications, then try again.")))
            return
        }
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first
        let saved = defaults.data(forKey: "chromeSession").flatMap { try? JSONDecoder().decode(ChromeSession.self, from: $0) }
        let session = reuse && saved?.processID == running?.processIdentifier && saved?.launchedAt == running?.launchDate ? saved : nil
        queue.async {
            do {
                let script = try ChromeScript.open(url: address, windowID: session?.windowID, tabID: session?.tabID)
                let process = Process()
                let output = Pipe()
                let errors = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]
                process.standardOutput = output
                process.standardError = errors
                try process.run()
                process.waitUntilExit()
                let result = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let error = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                guard process.terminationStatus == 0 else {
                    if error.contains("-1743") || error.contains("not authorized") {
                        throw LaunchError.message("Allow TabShelf to control Google Chrome in System Settings → Privacy & Security → Automation, then try again.")
                    }
                    throw LaunchError.message("Chrome couldn't open this page. \(error.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
                let ids = result.split(separator: ",").compactMap { Int($0) }
                DispatchQueue.main.async {
                    if ids.count == 2, let chrome = NSRunningApplication.runningApplications(withBundleIdentifier: "com.google.Chrome").first,
                       let date = chrome.launchDate, reuse {
                        let session = ChromeSession(processID: chrome.processIdentifier, launchedAt: date, windowID: ids[0], tabID: ids[1])
                        self.defaults.set(try? JSONEncoder().encode(session), forKey: "chromeSession")
                    }
                    completion(.success(()))
                }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    private func openInTopChrome(_ address: String, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: TopChromeLink.appID) else {
            completion(.failure(LaunchError.message("Open TopChrome once to register it, then try again. You can also choose Chrome in TabShelf Settings.")))
            return
        }
        do {
            let link = try TopChromeLink.make(address: address)
            NSWorkspace.shared.open([link], withApplicationAt: application, configuration: NSWorkspace.OpenConfiguration()) { _, error in
                DispatchQueue.main.async {
                    if let error { completion(.failure(error)) }
                    else { completion(.success(())) }
                }
            }
        } catch { completion(.failure(error)) }
    }
}

enum LaunchError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        if case .message(let value) = self { return value }
        return nil
    }
}
