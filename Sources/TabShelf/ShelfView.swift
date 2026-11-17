import AppKit
import SwiftUI
import TabShelfCore

private let shelfAccent = Color(red: 0.28, green: 0.36, blue: 0.87)

private enum ShelfEditor: Identifiable {
    case site(SavedSite?, UUID?)
    case group(SiteGroup?)
    case removeSite(SavedSite)
    case removeGroup(SiteGroup)

    var id: String {
        switch self {
        case .site(let site, _): return "site-\(site?.id.uuidString ?? "new")"
        case .group(let group): return "group-\(group?.id.uuidString ?? "new")"
        case .removeSite(let site): return "remove-site-\(site.id)"
        case .removeGroup(let group): return "remove-group-\(group.id)"
        }
    }
}

struct ShelfView: View {
    @ObservedObject var model: ShelfModel
    let showSettings: () -> Void
    @State private var search = ""
    @State private var editor: ShelfEditor?
    @State private var collapsedGroups: Set<UUID> = []

    private var filteredSites: [SavedSite] {
        model.document.matchingSites(search)
    }

    var body: some View {
        shelfContent
            .disabled(editor != nil)
            .accessibilityHidden(editor != nil)
            .overlay {
                if let editor {
                    ZStack {
                        Color.black.opacity(0.20).contentShape(Rectangle()).onTapGesture {}
                        dialog(editor)
                            .id(editor.id)
                            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                            .shadow(color: .black.opacity(0.20), radius: 16, y: 6)
                    }
                    .onExitCommand { self.editor = nil }
                }
            }
            .onDisappear { editor = nil }
    }

    private var shelfContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 21, weight: .medium)).foregroundStyle(shelfAccent)
                    .frame(width: 42, height: 42).background(shelfAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("TabShelf").font(.system(size: 19, weight: .semibold, design: .rounded))
                    Text("Your tabs, on standby.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(model.document.sites.count)").font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary).padding(.horizontal, 9).padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
            }.padding(20)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Find a saved site", text: $search).textFieldStyle(.plain).font(.system(size: 13))
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }.padding(10).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                .padding(.horizontal, 16).padding(.bottom, 12)

            Button { model.open(model.document.settings.newTabURL) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus").font(.system(size: 17, weight: .medium)).frame(width: 34, height: 34)
                        .background(shelfAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("New Tab").font(.system(size: 13, weight: .semibold))
                        Text(WebAddress.displayHost(model.document.settings.newTabURL)).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                }.foregroundStyle(shelfAccent).padding(10).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(model.opening || model.savingChromePage).padding(.horizontal, 10)

            Button(action: model.saveCurrentChromePage) {
                Label(model.savingChromePage ? "Saving from Chrome…" : "Save Current Chrome Tab", systemImage: "square.and.arrow.down")
                    .font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
            }.buttonStyle(.bordered).tint(shelfAccent).disabled(model.savingChromePage || model.opening)
                .padding(.horizontal, 16).padding(.top, 8)
                .help("Save the active tab in Chrome's front window. No extension needed.")

            HStack {
                Text("YOUR SHELF").font(.system(size: 10, weight: .semibold)).tracking(1.2)
                Spacer()
                Menu {
                    Picker("Open links in", selection: Binding(get: { model.document.settings.browserDestination }, set: model.setBrowserDestination)) {
                        Text("Chrome").tag(BrowserDestination.chrome)
                        Text("TopChrome").tag(BrowserDestination.topChrome)
                    }
                } label: {
                    Text("Open in \(model.document.settings.browserDestination == .topChrome ? "TopChrome" : "Chrome")")
                        .font(.system(size: 11, weight: .medium))
                }.menuStyle(.borderlessButton).fixedSize().help("Choose where saved sites and New Tab open")
                    .accessibilityLabel("Open links in")
            }.foregroundStyle(.secondary).padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 2) {
                    if filteredSites.isEmpty && (model.document.groups.isEmpty || !search.isEmpty) {
                        VStack(spacing: 10) {
                            Image(systemName: search.isEmpty ? "bookmark" : "magnifyingglass").font(.system(size: 25, weight: .light)).foregroundStyle(shelfAccent.opacity(0.7))
                            Text(search.isEmpty ? "A little shelf for your web." : "No matching sites").font(.system(size: 14, weight: .medium))
                            Text(search.isEmpty ? "Save the places you use. Open them when\nyou need them, and close them when you're done." : "Try another name or address.")
                                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(3)
                            if search.isEmpty {
                                Button("Add your first site") { editor = .site(nil, nil) }.buttonStyle(.borderedProminent).tint(shelfAccent).padding(.top, 2)
                            }
                        }.frame(maxWidth: .infinity).padding(.vertical, 30)
                    } else {
                        let pinned = model.document.pinnedSites(matching: search)
                        if !pinned.isEmpty {
                            sectionLabel("Pinned", symbol: "pin.fill")
                            siteRows(pinned)
                        }
                        ForEach(model.document.groups) { group in
                            groupSection(group)
                        }
                        let ungrouped = filteredSites.filter { !$0.isPinned && $0.groupID == nil }
                        if !ungrouped.isEmpty {
                            if !pinned.isEmpty || !model.document.groups.isEmpty {
                                sectionLabel("Ungrouped", symbol: "tray")
                            }
                            siteRows(ungrouped)
                        }
                    }
                }.padding(.horizontal, 10)
            }.frame(minHeight: 100, maxHeight: .infinity)

            if let error = model.error {
                Text(error).font(.system(size: 11)).foregroundStyle(.red).textSelection(.enabled)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 5) {
                    Image(systemName: model.notice == nil ? "checkmark.shield" : "checkmark.circle.fill")
                    Text(model.notice ?? "Saved here. Ready whenever.")
                }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.vertical, 10)
            }
            Divider()
            HStack {
                Button { editor = .site(nil, nil) } label: { Label("Add Site", systemImage: "plus") }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(shelfAccent)
                Button { editor = .group(nil) } label: { Label("New Group", systemImage: "folder.badge.plus") }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(shelfAccent).padding(.leading, 12)
                Spacer()
                Button(action: showSettings) { Image(systemName: "gearshape").font(.system(size: 14)) }
                    .buttonStyle(.plain).help("Settings").accessibilityLabel("Settings")
                Menu {
                    Button("Show Saved Data") { NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: TabShelfPaths.dataDirectory.path) }
                    Divider()
                    Button("Quit TabShelf") { NSApp.terminate(nil) }.keyboardShortcut("q")
                } label: { Image(systemName: "ellipsis.circle").font(.system(size: 14)) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("More").accessibilityLabel("More options")
            }.padding(.horizontal, 20).padding(.vertical, 14)
        }.frame(width: 390).background(.regularMaterial)
    }

    @ViewBuilder private func dialog(_ value: ShelfEditor) -> some View {
        switch value {
        case .site(let site, let groupID):
            SiteEditor(model: model, site: site, initialGroupID: groupID, dismiss: { editor = nil })
        case .group(let group):
            GroupEditor(model: model, group: group, dismiss: { editor = nil })
        case .removeSite(let site):
            RemovalConfirmation(title: "Remove this site?",
                                message: "“\(site.title)” will be removed from your saved list.",
                                actionTitle: "Remove", cancel: { editor = nil }) {
                model.remove(site)
                editor = nil
            }
        case .removeGroup(let group):
            RemovalConfirmation(title: "Remove this group?",
                                message: "“\(group.name)” will be removed. Its sites will move to Ungrouped, and pinned sites will stay pinned.",
                                actionTitle: "Remove Group", cancel: { editor = nil }) {
                model.removeGroup(group)
                editor = nil
            }
        }
    }

    private func sectionLabel(_ title: String, symbol: String) -> some View {
        Label(title.uppercased(), systemImage: symbol)
            .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 4)
    }

    private func siteRows(_ sites: [SavedSite]) -> some View {
        ForEach(sites) { site in
            SiteRow(site: site, groups: model.document.groups, disabled: model.opening || model.savingChromePage,
                    open: { model.open(site.url) }, edit: { editor = .site(site, nil) },
                    togglePin: { model.togglePin(site) }, move: { model.move(site, to: $0) },
                    remove: { editor = .removeSite(site) })
        }
    }

    @ViewBuilder private func groupSection(_ group: SiteGroup) -> some View {
        let sites = filteredSites.filter { !$0.isPinned && $0.groupID == group.id }
        if search.isEmpty || !sites.isEmpty {
            HStack(spacing: 6) {
                Button {
                    if collapsedGroups.contains(group.id) { collapsedGroups.remove(group.id) }
                    else { collapsedGroups.insert(group.id) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: collapsedGroups.contains(group.id) ? "chevron.right" : "chevron.down").font(.system(size: 9, weight: .semibold))
                        Image(systemName: "folder").foregroundStyle(shelfAccent)
                        Text(group.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Spacer()
                        Text("\(model.document.sites.filter { $0.groupID == group.id }.count)").font(.system(size: 10)).foregroundStyle(.secondary)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("\(collapsedGroups.contains(group.id) ? "Expand" : "Collapse") \(group.name)")
                Menu {
                    Button("Add Site to Group…") { editor = .site(nil, group.id) }
                    Button("Rename Group…") { editor = .group(group) }
                    Divider()
                    Button("Remove Group…", role: .destructive) { editor = .removeGroup(group) }
                } label: { Image(systemName: "ellipsis").frame(width: 22) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("Options for \(group.name)")
            }.padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 4)
            if !collapsedGroups.contains(group.id) || !search.isEmpty {
                if sites.isEmpty {
                    if model.document.sites.contains(where: { $0.groupID == group.id && $0.isPinned }) {
                        Text("Pinned sites appear above.").font(.system(size: 10)).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 32).padding(.top, 4)
                    }
                    Button("Add a site to this group") { editor = .site(nil, group.id) }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 32).padding(.vertical, 10)
                } else { siteRows(sites) }
            }
        }
    }
}

private struct SiteRow: View {
    let site: SavedSite
    let groups: [SiteGroup]
    let disabled: Bool
    let open: () -> Void
    let edit: () -> Void
    let togglePin: () -> Void
    let move: (UUID?) -> Void
    let remove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: open) {
                HStack(spacing: 12) {
                    Text(String(WebAddress.displayHost(site.url).prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(shelfAccent)
                        .frame(width: 34, height: 34).background(shelfAccent.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(site.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Text(WebAddress.displayHost(site.url) + (site.isPinned ? groups.first(where: { $0.id == site.groupID }).map { " · " + $0.name } ?? "" : ""))
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                }.padding(10).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(disabled).help(site.url)
            Button(action: togglePin) {
                Image(systemName: site.isPinned ? "pin.fill" : "pin").font(.system(size: 11))
                    .foregroundStyle(site.isPinned ? shelfAccent : Color.secondary).frame(width: 24, height: 36)
            }.buttonStyle(.plain).help(site.isPinned ? "Unpin" : "Pin to top").accessibilityLabel("\(site.isPinned ? "Unpin" : "Pin") \(site.title)")
            Button(action: remove) { Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 28, height: 36) }
                .buttonStyle(.plain).help("Remove \(site.title)").accessibilityLabel("Remove \(site.title)").padding(.trailing, 6)
        }.background(hovering ? Color.primary.opacity(0.045) : .clear, in: RoundedRectangle(cornerRadius: 9))
            .onHover { hovering = $0 }
            .contextMenu {
                Button("Open", action: open).disabled(disabled)
                Button("Edit Site…", action: edit)
                Button(site.isPinned ? "Unpin" : "Pin to Top", action: togglePin)
                Menu("Move to Group") {
                    Button("Ungrouped") { move(nil) }
                    ForEach(groups) { group in Button(group.name) { move(group.id) } }
                }
                Button("Copy URL") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(site.url, forType: .string)
                }
                Divider()
                Button("Remove…", role: .destructive, action: remove)
            }
    }
}

private struct RemovalConfirmation: View {
    let title: String
    let message: String
    let actionTitle: String
    let cancel: () -> Void
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.system(size: 19, weight: .semibold, design: .rounded))
            Text(message).font(.system(size: 13)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button(actionTitle, role: .destructive, action: remove)
                    .buttonStyle(.borderedProminent).tint(.red)
            }
        }.padding(24).frame(width: 350)
            .accessibilityElement(children: .contain)
    }
}

private struct SiteEditor: View {
    @ObservedObject var model: ShelfModel
    let site: SavedSite?
    let initialGroupID: UUID?
    let dismiss: () -> Void
    @State private var title = ""
    @State private var url = ""
    @State private var error: String?
    @State private var groupID: UUID?
    @State private var pinned = false
    @FocusState private var urlFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(site == nil ? "Add a site" : "Edit site").font(.system(size: 19, weight: .semibold, design: .rounded))
            VStack(alignment: .leading, spacing: 6) {
                Text("Address").font(.system(size: 12, weight: .medium))
                TextField("https://example.com", text: $url).textFieldStyle(.roundedBorder).focused($urlFocused)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Name (optional)").font(.system(size: 12, weight: .medium))
                TextField("A name you'll recognize", text: $title).textFieldStyle(.roundedBorder)
            }
            Picker("Group", selection: $groupID) {
                Text("Ungrouped").tag(UUID?.none)
                ForEach(model.document.groups) { group in Text(group.name).tag(Optional(group.id)) }
            }
            Toggle("Pin to the top of my shelf", isOn: $pinned)
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Site") {
                    do { try model.save(id: site?.id, title: title, url: url, groupID: groupID, pinned: pinned); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(shelfAccent)
            }
        }.padding(24).frame(width: 340)
            .onAppear {
                title = site?.title ?? ""; url = site?.url ?? ""
                groupID = site?.groupID ?? initialGroupID; pinned = site?.isPinned ?? false; urlFocused = true
            }
    }
}

private struct GroupEditor: View {
    @ObservedObject var model: ShelfModel
    let group: SiteGroup?
    let dismiss: () -> Void
    @State private var name = ""
    @State private var error: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(group == nil ? "New group" : "Rename group").font(.system(size: 19, weight: .semibold, design: .rounded))
            TextField("Work, Reading, Projects…", text: $name).textFieldStyle(.roundedBorder).focused($nameFocused)
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(group == nil ? "Create Group" : "Save Name") {
                    do { try model.saveGroup(id: group?.id, name: name); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).tint(shelfAccent)
            }
        }.padding(24).frame(width: 340)
            .onAppear { name = group?.name ?? ""; nameFocused = true }
    }
}
