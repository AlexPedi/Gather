import SwiftUI
import GatherCore
import UniformTypeIdentifiers

struct LibraryView: View {
    @Bindable var model: AppModel
    @ViewState<Bool> private var targeted = false
    @ViewState<[UUID: CGRect]> private var screenshotFrames = [:]
    @FocusState private var libraryFocused: Bool
    @ViewState<CGFloat> private var libraryWidth: CGFloat = 760
    private var keyboardColumns: Int { model.listMode ? 1 : max(1, Int((libraryWidth - 48 + 16) / (model.thumbnailSize + 16))) }
    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 280)
        } detail: {
            center.navigationSplitViewColumnWidth(min: 420, ideal: 760)
        }
        .inspector(isPresented: Binding(
            get: { model.selected != nil && !model.batchMode },
            set: { if !$0 && !model.batchMode { model.selectedID = nil } }
        )) {
            if let item = model.selected {
                InspectorView(model: model, item: item).id(item.id)
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
            }
        }
        .navigationTitle("Gather")
        .onExitCommand {
            if model.batchMode { model.endBatchSelection() }
        }
        .onChange(of: model.selectedID) { _, id in
            if let id, !model.batchMode { model.markViewed(id); libraryFocused = true }
        }
        .disabled(model.batchBusy || model.deleting)
        .onChange(of: Set(model.visible.map(\.id))) { _, ids in model.batchSelection.formIntersection(ids) }
        .onChange(of: model.scope) { _, _ in model.categoryFilter = nil; model.tagFilter = nil }
        .toolbar {
            ToolbarItem {
                Button(model.batchMode ? "Done Selecting" : "Select") {
                    if model.batchMode { model.endBatchSelection() } else { model.batchMode = true; model.batchSelection = [] }
                }.disabled(model.items.isEmpty || model.cleanupBusy)
            }
            ToolbarItem {
                Menu {
                    Button("Import Images…", action: model.chooseFiles)
                    Button("Scan Screenshot Folder…", action: model.chooseFolder)
                    Button("Watch Screenshot Folder…", action: model.chooseWatchFolder)
                    Divider()
                    Button("Organize Desktop…", action: model.openOrganizer).disabled(model.cleanupBusy || model.busy)
                    Button("File Operations…") { model.showCleanupHistory = true }
                    Divider()
                    Button("New Tag…") { model.showNewTag = true }
                    Button("Manage Tags…") { model.showTagManager = true }
                } label: {
                    Label("Import", systemImage: "plus").labelStyle(.titleAndIcon)
                }.menuStyle(.borderedButton).menuIndicator(.visible).fixedSize()
                    .accessibilityLabel("Import screenshots").help("Import images or connect a screenshot folder").disabled(model.busy)
            }
            ToolbarItem {
                Picker("View", selection: $model.listMode) {
                    Image(systemName: "square.grid.2x2").tag(false)
                    Image(systemName: "list.bullet").tag(true)
                }.pickerStyle(.segmented).frame(width: 78).accessibilityLabel("Grid or list view")
            }
            ToolbarItem {
                Menu {
                    Picker("Sort", selection: $model.sort) { ForEach(SortOrder.allCases, id: \.self) { Text($0.rawValue).tag($0) } }
                } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
            }
        }
        .alert("Gather Needs Your Attention", isPresented: Binding(get: { model.error != nil && !model.showTagManager && model.reviewGroup == nil && !model.showOrganizer && !model.showCleanupHistory && !model.showBatchTags && !model.showOnboarding }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .confirmationDialog(model.pendingDeletion.count == 1 ? "Delete screenshot?" : "Delete \(model.pendingDeletion.count) screenshots?", isPresented: $model.showDeleteConfirmation, titleVisibility: .visible) {
            Button("Move to Trash", role: .destructive) { model.deleteConfirmed() }
            Button("Cancel", role: .cancel) { model.pendingDeletion = [] }
        } message: {
            Text("The original files will move to Trash and the screenshots will be removed from Gather and all collections. You can recover the files from Trash in Finder.")
        }
        .sheet(isPresented: $model.showOnboarding) { OnboardingView(model: model, loginItem: AppSession.shared.loginItem) }
        .sheet(item: $model.pendingScan) { scan in
            VStack(alignment: .leading, spacing: 20) {
                Label("Ready to gather", systemImage: "photo.stack").font(.title2.bold())
                Text("\(scan.urls.count) likely screenshots found in \(scan.folder.lastPathComponent).")
                Text("Gather checks this folder’s immediate contents using filenames and screenshot metadata. Files stay exactly where they are.").foregroundStyle(.secondary)
                if scan.urls.isEmpty { Text("Use Import Images to select images with other filenames.").font(.callout) }
                HStack {
                    Button("Cancel") { model.pendingScan = nil }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Import \(scan.urls.count) Screenshots") {
                        model.pendingScan = nil; model.importURLs(scan.urls, authorizedFolder: scan.folder)
                    }.keyboardShortcut(.defaultAction).disabled(scan.urls.isEmpty)
                }
            }.padding(28).frame(width: 470)
        }
        .sheet(item: Binding(get: { model.reviewGroup == nil ? model.imagePreview : nil }, set: { model.imagePreview = $0 })) { item in
            ImagePreviewView(item: item, cache: model.cache)
        }
        .sheet(isPresented: $model.showBatchTags) { BatchTagsView(model: model) }
        .sheet(isPresented: $model.showOrganizer) { OrganizeDesktopView(model: model) }
        .sheet(isPresented: $model.showCleanupHistory) { CleanupHistoryView(model: model) }
        .sheet(item: $model.reviewGroup) { group in GroupReviewView(model: model, group: group) }
        .sheet(isPresented: $model.showTagManager) { TagManagerView(model: model).interactiveDismissDisabled(model.tagManagementBusy) }
        .sheet(isPresented: $model.showNewTag) {
            VStack(alignment: .leading, spacing: 18) {
                Label("Create Tag", systemImage: "tag").font(.title2.bold())
                TextField("Tag name", text: $model.newTagName).textFieldStyle(.roundedBorder).onSubmit { model.createTag() }
                Text("Up to 60 characters, without commas. Tags can be reused across your library.").font(.caption).foregroundStyle(.secondary)
                Toggle("Add to selected screenshot", isOn: $model.applyNewTagToSelection).disabled(model.selectedID == nil)
                HStack {
                    Button("Cancel") { model.showNewTag = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Create Tag") { model.createTag() }.keyboardShortcut(.defaultAction)
                        .disabled(model.newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.newTagName.count > 60 || model.newTagName.contains(","))
                }
            }.padding(28).frame(width: 430)
        }
        .sheet(isPresented: $model.newCollection) {
            VStack(alignment: .leading, spacing: 20) {
                Text("New Collection").font(.title2.bold())
                TextField("Collection name", text: $model.collectionName).onSubmit { addCollection() }
                HStack {
                    Button("Cancel") { model.newCollection = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Create", action: addCollection).keyboardShortcut(.defaultAction).disabled(model.collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(28).frame(width: 360)
        }
    }

    func addCollection() {
        guard !model.collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        model.createCollection(); model.newCollection = false
    }
    var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.fill").font(.title3).foregroundStyle(GatherTheme.accent)
                Text("Gather").font(.system(size: 18, weight: .semibold))
            }.padding(22)
            List(selection: $model.scope) {
                Section("Library") {
                    sidebarRow("All Screenshots", icon: "square.grid.2x2", count: model.items.count).tag(LibraryScope.all)
                    sidebarRow("Inbox", icon: "tray", count: model.items.filter(\.inbox).count).tag(LibraryScope.inbox)
                    sidebarRow("Favorites", icon: "heart", count: model.items.filter(\.favorite).count).tag(LibraryScope.favorites)
                }
                Section("Automatic groups") {
                    ForEach(GatherCore.Category.allCases.filter { category in category != .uncategorized && model.items.contains { $0.category == category } }, id: \.self) { category in
                        Label(category.rawValue, systemImage: "sparkles").tag(LibraryScope.automaticCategory(category))
                    }
                    ForEach(model.automaticGroups) { group in
                        HStack {
                            Label(group.title, systemImage: "square.stack")
                            Spacer()
                            Text("\(group.itemIDs.count)").font(.caption).foregroundStyle(.secondary)
                        }.tag(LibraryScope.related(group.id))
                        .contextMenu {
                            Button("Review Group…") { model.keepGroup(group) }
                            Button("Dismiss Group") { model.dismissGroup(group) }
                        }
                    }
                }
                Section {
                    ForEach(model.collections) { collection in
                        Label(collection.name, systemImage: "folder").tag(LibraryScope.collection(collection.id))
                    }
                    Button { model.newCollection = true } label: { Label("New Collection", systemImage: "plus") }.buttonStyle(.plain).foregroundStyle(.secondary)
                } header: { Text("Collections") }
            }.listStyle(.sidebar)
            VStack(alignment: .leading, spacing: 8) {
                if model.automation.watchedPaths.isEmpty {
                    Button("Watch Screenshot Folder…", action: model.chooseWatchFolder).font(.caption)
                }
                Label(model.watchStatus.isEmpty ? "Starting automatic intake…" : model.watchStatus, systemImage: model.automation.watchedPaths.isEmpty || !model.automation.intakeEnabled ? "pause.circle" : "circle.fill")
                    .font(.caption2).foregroundStyle(model.watchStatus.contains(":") ? Color.orange : Color.secondary)
                Text("Private. Local. Yours.").font(.caption2).foregroundStyle(.tertiary)
            }.padding(18)
        }
    }
    func sidebarRow(_ name: String, icon: String, count: Int) -> some View {
        HStack { Label(name, systemImage: icon); Spacer(); Text(count.formatted()).font(.caption).foregroundStyle(.secondary) }
    }
    func filterChip(_ title: String, tag: String?) -> some View {
        Button { model.tagFilter = tag } label: {
            HStack(spacing: 5) {
                Text(title)
                if let tag { Text("\(model.tagCount(tag))").foregroundStyle(.secondary).font(.caption2) }
            }.font(.system(size: 12, weight: model.tagFilter == tag ? .semibold : .regular))
                .padding(.horizontal, 14).padding(.vertical, 7)
                .foregroundStyle(model.tagFilter == tag ? GatherTheme.accent : Color.secondary)
                .background(model.tagFilter == tag ? GatherTheme.accent.opacity(0.14) : Color.primary.opacity(0.035), in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(model.tagFilter == tag ? .isSelected : [])
    }
    var center: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.scopeTitle).font(.system(size: 26, weight: .semibold))
                    Text(model.scope == .inbox ? "Everything you captured. Ready to organize." : "Your screenshots, all in one place.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                if !model.listMode {
                    Image(systemName: "photo").foregroundStyle(.tertiary)
                    Slider(value: $model.thumbnailSize, in: 160...320).frame(width: 85).accessibilityLabel("Thumbnail size")
                }
            }.padding(24)
            VStack(alignment: .leading, spacing: 9) {
                Text("Find what you saved").font(.system(size: 15, weight: .semibold))
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").font(.system(size: 18)).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    NativeSearchField(text: $model.query, focusRequest: model.searchFocusRequest)
                        .frame(height: 24)
                    if !model.query.isEmpty {
                        Button { model.query = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }.buttonStyle(.plain).accessibilityLabel("Clear search").help("Clear search")
                    }
                    Button { model.searchFocusRequest += 1 } label: {
                        Text("⌘ F").font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
                    }.buttonStyle(.plain).accessibilityLabel("Focus screenshot search")
                }.frame(minHeight: 34).padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
                    .overlay(RoundedRectangle(cornerRadius: 11).stroke(GatherTheme.accent.opacity(0.4), lineWidth: 1.5))
                Text("Search the text inside your screenshots, titles, and tags.").font(.system(size: 12)).foregroundStyle(.secondary)
            }.padding(.horizontal, 24).padding(.bottom, 22)
            if model.pendingCount > 0 || !model.automation.indexingEnabled {
                HStack {
                    if model.automation.indexingEnabled { ProgressView().controlSize(.small) }
                    Text(model.automation.indexingEnabled ? "Organizing \(model.pendingCount) screenshots on your Mac…" : "Automatic organization paused")
                    Spacer()
                }.font(.caption).foregroundStyle(GatherTheme.accent).padding(12)
                    .background(GatherTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 24).padding(.bottom, 12)
            }
            if case .related(let id) = model.scope, let group = model.automaticGroups.first(where: { $0.id == id }) {
                HStack {
                    Text(group.reason).font(.caption)
                    Spacer()
                    Button("Review Group…") { model.keepGroup(group) }
                    Button("Dismiss") { model.dismissGroup(group) }
                }.padding(.horizontal, 24).padding(.bottom, 12)
            }
            if !model.items.isEmpty || !model.availableTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip("All", tag: nil)
                        ForEach(model.availableTags, id: \.self) { tag in
                            filterChip(tag, tag: tag).contextMenu {
                                Button("Manage Tags…") { model.showTagManager = true }
                            }
                        }
                        Button { model.showNewTag = true } label: { Label("New Tag", systemImage: "plus") }.buttonStyle(.borderless).font(.caption)
                        Button("Manage Tags…") { model.showTagManager = true }.buttonStyle(.borderless).font(.caption)
                    }.padding(.horizontal, 24).padding(.bottom, 16)
                }
            }
            if model.batchMode { BatchActionBar(model: model).padding(.horizontal, 24).padding(.bottom, 12) }
            if model.loading { Spacer(); ProgressView("Opening your library…"); Spacer() }
            else if model.items.isEmpty {
                ContentUnavailableView {
                    Label("Make room for clarity", systemImage: "photo.on.rectangle.angled")
                } description: {
                    Text("Gather your screenshots into one calm place.\nImport images, scan your Desktop, or drop files here.")
                } actions: {
                    HStack {
                        Button("Import Images…", action: model.chooseFiles).buttonStyle(.borderedProminent)
                        Button("Scan Desktop…", action: model.chooseFolder)
                    }.disabled(model.busy)
                }.frame(maxHeight: .infinity)
            } else if model.visible.isEmpty {
                let inboxDone = model.scope == .inbox && model.query.isEmpty && !model.items.contains(where: \.inbox)
                ContentUnavailableView(inboxDone ? "You’re all caught up" : "No screenshots here", systemImage: inboxDone ? "checkmark.circle" : "magnifyingglass", description: Text(inboxDone ? "Every screenshot has been reviewed. You can still find them in All Screenshots." : model.query.isEmpty ? "Try a different tag or collection." : "Try a different title, filename, category, or tag.")).frame(maxHeight: .infinity)
            } else if model.listMode {
                List(selection: $model.selectedID) {
                    ForEach(model.visible) { item in
                        HStack(spacing: 14) {
                            if model.batchMode {
                                Toggle("Select \(item.title)", isOn: Binding(get: { model.batchSelection.contains(item.id) }, set: { _ in model.toggleBatchSelection(item.id) })).labelsHidden().toggleStyle(.checkbox).accessibilityLabel("Select \(item.title)")
                            }
                            ScreenshotImage(item: item, cache: model.cache).frame(width: 76, height: 54).clipShape(RoundedRectangle(cornerRadius: 5))
                            VStack(alignment: .leading, spacing: 4) { Text(item.title).lineLimit(1); Text(item.tags.isEmpty ? "No tags yet" : item.tags.prefix(3).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                            Spacer()
                            if !model.batchMode { CopyScreenshotTextButton(model: model, item: item) }
                            if item.favorite { Image(systemName: "star.fill").foregroundStyle(.purple) }
                            Text(item.captureDate, style: .date).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 5).contentShape(Rectangle()).tag(item.id)
                            .contextMenu {
                                Button(model.batchSelection.contains(item.id) ? "Deselect Screenshot" : "Select Screenshot") {
                                    model.batchMode = true; model.toggleBatchSelection(item.id)
                                }
                                Button("Delete Screenshot…", role: .destructive) { model.requestDeletion([item.id]) }.disabled(!model.canDelete)
                            }
                            .onTapGesture(count: 2) { if !model.batchMode { model.openImage(item) } }
                            .nativeFileDrag(item: item, model: model) { if model.batchMode { model.toggleBatchSelection(item.id) } else { model.selectedID = item.id } }
                    }
                }.listStyle(.inset)
            } else {
                ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(model.dateGroups.enumerated()), id: \.offset) { _, group in
                            HStack {
                                Text(group.title).font(.headline)
                                Spacer()
                                Text("\(group.items.count) screenshots").font(.caption).foregroundStyle(.secondary)
                            }
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: model.thumbnailSize), spacing: 16)], spacing: 18) {
                                ForEach(group.items) { item in
                                    Button { if model.batchMode { model.toggleBatchSelection(item.id) } else { model.selectedID = item.id } } label: {
                                        ScreenshotCard(item: item, cache: model.cache, selected: model.batchMode ? model.batchSelection.contains(item.id) : model.selectedID == item.id)
                                            .overlay(alignment: .topLeading) {
                                                if model.batchMode { Image(systemName: model.batchSelection.contains(item.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(model.batchSelection.contains(item.id) ? GatherTheme.accent : .secondary).font(.title2).padding(10).background(.regularMaterial, in: Circle()).padding(7) }
                                            }
                                    }.id(item.id).buttonStyle(.plain).accessibilityLabel(model.batchMode ? "Select \(item.title)" : "\(item.title), \(item.category.rawValue)")
                                        .accessibilityAddTraits(model.batchMode && model.batchSelection.contains(item.id) ? .isSelected : [])
                                        .simultaneousGesture(TapGesture(count: 2).onEnded {
                                            if !model.batchMode { model.openImage(item) }
                                        })
                                        .nativeFileDrag(item: item, model: model) { if model.batchMode { model.toggleBatchSelection(item.id) } else { model.selectedID = item.id } }
                                        .overlay(alignment: .topTrailing) {
                                            if !model.batchMode {
                                                CopyScreenshotTextButton(model: model, item: item)
                                                    .buttonStyle(.bordered).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                                                    .padding(.top, item.favorite ? 46 : 10).padding(.trailing, 10)
                                            }
                                        }
                                        .background(GeometryReader { geometry in
                                            Color.clear.preference(key: ScreenshotFrames.self, value: [item.id: geometry.frame(in: .named("screenshotGrid"))])
                                        })
                                        .contextMenu {
                                            Button("Copy Text") { model.copyText(item) }
                                                .disabled(item.extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                            Button(item.favorite ? "Remove Favorite" : "Favorite") { model.update(item.id) { $0.favorite.toggle() } }
                                            Button("Show in Finder") { model.showInFinder(item) }
                                            Button("Open Image") { model.openImage(item) }
                                            Divider()
                                            Button("Delete Screenshot…", role: .destructive) { model.requestDeletion([item.id]) }.disabled(!model.canDelete)
                                        }
                                }
                            }
                        }
                    }.padding(24)
                        .coordinateSpace(name: "screenshotGrid")
                        .onPreferenceChange(ScreenshotFrames.self) { screenshotFrames = $0 }
                        .overlay { MarqueeSelection(model: model, frames: screenshotFrames) }
                }
                .onChange(of: model.selectedID) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .center) }
                }
                }
            }
            Divider()
            HStack(spacing: 8) {
                if model.deleting { ProgressView().controlSize(.small); Text("Moving screenshots to Trash…") }
                else if model.busy { ProgressView().controlSize(.small); Text(model.progress) }
                else { Text(model.notice.isEmpty ? "\(model.visible.count) screenshots · Sorted by \(model.sort.rawValue.lowercased())" : model.notice) }
                Spacer()
            }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 10)
        }
        .background(GeometryReader { geometry in
            Color.clear.onAppear { libraryWidth = geometry.size.width }
                .onChange(of: geometry.size.width) { _, width in libraryWidth = width }
        })
        .focusable()
        .focused($libraryFocused)
        .onAppear { libraryFocused = true }
        .onKeyPress(.space) {
            guard !model.batchMode, let item = model.selected else { return .ignored }
            model.openImage(item)
            return .handled
        }
        .onMoveCommand { model.moveSelection($0, columns: keyboardColumns) }
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay { if targeted { RoundedRectangle(cornerRadius: 12).stroke(.purple, style: StrokeStyle(lineWidth: 3, dash: [8])).padding(8).allowsHitTesting(false) } }
        .dropDestination(for: URL.self) { urls, _ in
            model.acceptDrop(urls)
        } isTargeted: { targeted = $0 }
    }
}
