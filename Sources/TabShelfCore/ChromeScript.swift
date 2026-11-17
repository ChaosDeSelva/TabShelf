import Foundation

public enum ChromeScript {
    public static let currentTab = """
    with timeout of 15 seconds
        if application id "com.google.Chrome" is not running then error "Open a website in Chrome first."
        tell application id "com.google.Chrome"
            if (count of windows) is 0 then error "Open a website in Chrome first."
            set currentPage to active tab of front window
            return (URL of currentPage as text) & linefeed & (title of currentPage as text)
        end tell
    end timeout
    """

    public static func open(url: String, windowID: Int?, tabID: Int?) throws -> String {
        let normalized = try WebAddress.normalize(url)
        let quoted = normalized.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let window = windowID ?? -1
        let tab = tabID ?? -1
        return """
        with timeout of 30 seconds
            tell application id "com.google.Chrome"
                set shelfWindow to missing value
                set shelfTab to missing value
                repeat with candidate in windows
                    if (id of candidate as integer) is \(window) then
                        repeat with candidateTab in tabs of candidate
                            if (id of candidateTab as integer) is \(tab) then
                                set shelfWindow to candidate
                                set shelfTab to candidateTab
                                exit repeat
                            end if
                        end repeat
                    end if
                end repeat
                if shelfWindow is missing value then
                    set shelfWindow to make new window
                    set shelfTab to active tab of shelfWindow
                end if
                set URL of shelfTab to "\(quoted)"
                set tabPosition to 1
                repeat with candidateTab in tabs of shelfWindow
                    if (id of candidateTab) is (id of shelfTab) then
                        set active tab index of shelfWindow to tabPosition
                        exit repeat
                    end if
                    set tabPosition to tabPosition + 1
                end repeat
                set minimized of shelfWindow to false
                set index of shelfWindow to 1
                activate
                return (id of shelfWindow as text) & "," & (id of shelfTab as text)
            end tell
        end timeout
        """
    }
}

public struct ChromePage {
    public let url: String
    public let title: String

    public init(scriptOutput: String) throws {
        // Split once: page titles can contain newlines, but a valid saved URL cannot.
        let fields = scriptOutput.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard fields.count == 2 else { throw ShelfError.invalidMessage }
        url = try WebAddress.normalize(String(fields[0]))
        title = SavedSite.cleanTitle(String(fields[1]), url: url)
    }
}
