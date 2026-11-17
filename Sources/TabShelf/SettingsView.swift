import ServiceManagement
import SwiftUI
import TabShelfCore

struct SettingsView: View {
    @ObservedObject var model: ShelfModel
    @State private var defaultURL = ""
    @State private var reuse = true
    @State private var destination = BrowserDestination.chrome
    @State private var launchAtLogin = false
    @State private var message: String?
    @State private var failed = false

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                Image(systemName: "rectangle.stack.fill").font(.system(size: 27)).foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Make yourself at home.").font(.system(size: 21, weight: .semibold, design: .rounded))
                    Text("A few small things, just how you like them.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    Text("BROWSING").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
                    Picker("Open links in", selection: $destination) {
                        Text("Chrome").tag(BrowserDestination.chrome)
                        Text("TopChrome").tag(BrowserDestination.topChrome)
                    }
                    .pickerStyle(.segmented)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("New Tab opens").font(.system(size: 12, weight: .medium))
                        TextField("https://www.google.com/", text: $defaultURL).textFieldStyle(.roundedBorder)
                    }
                    Toggle("Reuse one dedicated Chrome window", isOn: $reuse)
                        .disabled(destination == .topChrome)
                    Text(destination == .topChrome
                         ? "Sites and New Tab open as new tabs in TopChrome's drawer. Your Chrome window preference is kept for when you switch back."
                         : "Each site replaces the page in your TabShelf tab. Turn off to open a new window each time.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Spacer()
                        Button("Save Preferences", action: save).buttonStyle(.borderedProminent).tint(.indigo)
                    }
                }.padding(10)
            }
            Toggle("Start TabShelf when I log in", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Label("Save straight from Chrome", systemImage: "square.and.arrow.down").font(.system(size: 14, weight: .semibold))
                Text("Use Save Current Chrome Tab in the shelf. It saves the active page from Chrome's front window—no extension required.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Optional Chrome toolbar button: enable Developer mode at chrome://extensions, click Load unpacked, and select the extension folder.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Show Extension Folder") {
                        do { try ExtensionSetup.reveal(); message = "Files are ready. Chrome still needs Load unpacked to enable the optional extension."; failed = false }
                        catch { message = error.localizedDescription; failed = true }
                    }
                    Button("Copy Extensions Address") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("chrome://extensions", forType: .string)
                        message = "Copied chrome://extensions"; failed = false
                    }
                }
            }
            if let message {
                Text(message).font(.system(size: 11)).foregroundStyle(failed ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.padding(26)
        }.frame(width: 500, height: 630)
            .onAppear {
                defaultURL = model.document.settings.newTabURL
                reuse = model.document.settings.reuseWindow
                destination = model.document.settings.browserDestination
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
    }

    private func save() {
        do {
            var settings = model.document.settings
            settings.newTabURL = defaultURL
            settings.reuseWindow = reuse
            settings.browserDestination = destination
            try model.saveSettings(settings)
            defaultURL = model.document.settings.newTabURL
            message = "Preferences saved."; failed = false
        } catch { message = error.localizedDescription; failed = true }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = enabled
            if SMAppService.mainApp.status == .requiresApproval {
                message = "Approve TabShelf in System Settings → General → Login Items."
            } else { message = enabled ? "TabShelf will start at login." : "Start at login is off." }
            failed = false
        } catch {
            message = error.localizedDescription
            failed = true
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
