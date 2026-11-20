import SwiftUI
import AppKit
import UniformTypeIdentifiers
import GatherCore

enum LibraryScope: Hashable {
    case all, inbox, favorites, collection(UUID), automaticCategory(GatherCore.Category), related(String)
}
enum ReviewFilter: String, CaseIterable { case all = "All", unreviewed = "Unreviewed", reviewed = "Reviewed" }
enum OCRFilter: String, CaseIterable { case all = "All", complete = "Complete", pending = "Pending", failed = "Failed" }
enum SortOrder: String, CaseIterable { case newest = "Newest first", oldest = "Oldest first", title = "Title" }
struct Scan: Identifiable {
    let id = UUID()
    var folder: URL
    var urls: [URL]
}

@MainActor @Observable final class AppModel {
    var items: [Screenshot] = []
    var collections: [GatherCore.Collection] = []
    var permissions: [SavedAccess] = []
    var scope: LibraryScope? = .all
    var batchMode = false
    var batchSelection: Set<UUID> = []
    var batchBusy = false
    var showBatchTags = false
    private var batchTask: Task<Void, Never>?
    var pendingDeletion: Set<UUID> = []
    var showDeleteConfirmation = false
    var deleting = false
    private var deletionTask: Task<Void, Never>?
    var canDelete: Bool { !deleting && !busy && !batchBusy && !cleanupBusy && !loading }
    func requestDeletion(_ ids: Set<UUID>) {
        guard canDelete, !ids.isEmpty else { return }
        pendingDeletion = ids
        showDeleteConfirmation = true
    }
    func deleteConfirmed() {
        let ids = pendingDeletion
        pendingDeletion = []
        guard canDelete, !ids.isEmpty else { return }
        deleting = true; editRevision += 1
        deletionTask = Task {
            defer { deleting = false }
            await persistenceTask?.value
            var deleted: Set<UUID> = []
            var failures: [String] = []
            for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
                let title = items.first { $0.id == id }?.title ?? "Screenshot"
                do { try await store.trashScreenshot(id); deleted.insert(id) }
                catch { failures.append("\(title): \(error.localizedDescription)") }
            }
            items.removeAll { deleted.contains($0.id) }
            if let id = selectedID, deleted.contains(id) { selectedID = nil }
            if let preview = imagePreview, deleted.contains(preview.id) { imagePreview = nil }
            batchSelection.subtract(deleted)
            if batchMode && batchSelection.isEmpty { endBatchSelection() }
            do { try await reload() } catch { failures.append(error.localizedDescription) }
            notice = "Moved \(deleted.count) screenshot\(deleted.count == 1 ? "" : "s") to Trash"
            if !failures.isEmpty { error = failures.joined(separator: "\n") }
        }
    }
    var copiedTextID: UUID?
    private var copyFeedbackTask: Task<Void, Never>?

    func copyText(_ item: Screenshot) {
        guard !item.extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(item.extractedText, forType: .string) else { return }
        copyFeedbackTask?.cancel()
        copiedTextID = item.id
        copyFeedbackTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            self?.copiedTextID = nil
        }
    }

    var selectedID: UUID?
    var query = "" { didSet { scheduleSearch() } }
    var searchFocusRequest = 0
    var searchMatches: Set<UUID>?
    private var settingsTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    var automation = AutomationSettings()
    var automaticGroups: [AutomaticGroup] = []
    var reviewGroup: AutomaticGroup?
    var groupReviewBusy = false
    var reviewedGroupCount = 0
    private var groupReviewRevision = 0
    private var groupDecisionTask: Task<Void, Never>?
    var watchStatus = ""
    var indexingStatus = ""
    private var watchTask: Task<Void, Never>?
    private var indexingTask: Task<Void, Never>?
    private var didLoad = false
    private var editRevision = 0
    var tagFilter: String?
    var customTags: [String] = []
    private var tagCounts: [String: Int] = [:]
    private var tagNames: [String] = []
    var showNewTag = false
    var showTagManager = false
    var tagManagementBusy = false
    var hiddenTags: [String] = []
    private var currentTagRules = TagRules()
    var newTagName = ""
    var applyNewTagToSelection = true
    private var tagCatalogTask: Task<Void, Never>?
    var categoryFilter: GatherCore.Category?
    var favoritesOnly = false
    var reviewFilter: ReviewFilter = .all
    var ocrFilter: OCRFilter = .all
    var dateFilterEnabled = false
    var dateFrom = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    var dateThrough = Date()
    var hasSearchFilters: Bool { categoryFilter != nil || favoritesOnly || reviewFilter != .all || ocrFilter != .all || dateFilterEnabled || tagFilter != nil }
    func clearSearchFilters() {
        categoryFilter = nil; favoritesOnly = false; reviewFilter = .all; ocrFilter = .all
        dateFilterEnabled = false; tagFilter = nil
    }
    var sort: SortOrder = .newest
    var listMode = false
    var thumbnailSize: Double = 220
    var onboarding = OnboardingState()
    var showOnboarding = false
    var onboardingBusy = false
    var onboardingError: String?
    private var restoredSetupFolders: Set<String> = []
    private var onboardingTask: Task<Void, Never>?
    var loading = true
    var busy = false
    var progress = ""
    var notice = ""
    var error: String?
    var pendingScan: Scan?
    var newCollection = false
    var collectionName = ""
    var imagePreview: Screenshot?
    var showOrganizer = false
    var showCleanupHistory = false
    var cleanupPreview: CleanupOperation?
    var cleanupHistory: [CleanupOperation] = []
    var cleanupBusy = false
    var cleanupStatus = ""
    private var cleanupTask: Task<Void, Never>?
    private var persistenceTask: Task<Void, Never>?
    let store: LibraryStore
    let access = FileAccess()
    let cache: ThumbnailCache
    let dragDirectory: URL
    let importer: Importer
    let watcher: FolderWatcher
    let ocr: OCRWorker
    let cleanup: CleanupService

    init() throws {
        // A separately packaged development bundle can use an isolated library for UI checks.
        let developmentPath = Bundle.main.object(forInfoDictionaryKey: "GatherDevelopmentDataDirectory") as? String
        let base: URL
        if let developmentPath { base = URL(fileURLWithPath: developmentPath, isDirectory: true) }
        else { base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Gather", isDirectory: true) }
        store = try LibraryStore(url: base.appendingPathComponent("Library.sqlite"))
        importer = Importer(store: store)
        watcher = FolderWatcher(importer: importer)
        ocr = OCRWorker(store: store)
        cleanup = CleanupService(store: store)
        let caches = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        dragDirectory = developmentPath == nil ? caches.appendingPathComponent("Gather/DragExports") : base.appendingPathComponent("DragExports")
        cache = try ThumbnailCache(directory: developmentPath == nil ? caches.appendingPathComponent("Gather/Thumbnails") : base.appendingPathComponent("Thumbnails"))
    }
    var selected: Screenshot? { items.first { $0.id == selectedID } }
    var scopeTitle: String {
        switch scope {
        case .inbox: "Inbox"
        case .favorites: "Favorites"
        case .automaticCategory(let category): category.rawValue
        case .related(let id): automaticGroups.first { $0.id == id }?.title ?? "Related screenshots"
        case .collection(let id): collections.first { $0.id == id }?.name ?? "Collection"
        default: "All Screenshots"
        }
    }
    var visible: [Screenshot] {
        items.filter { item in
            let inScope: Bool
            switch scope {
            case .inbox: inScope = item.inbox
            case .favorites: inScope = item.favorite
            case .automaticCategory(let category): inScope = item.category == category
            case .related(let id): inScope = automaticGroups.first { $0.id == id }?.itemIDs.contains(item.id) == true
            case .collection(let id): inScope = item.collections.contains(id)
            default: inScope = true
            }
            let names = collections.filter { item.collections.contains($0.id) }.map(\.name)
            let text = ([item.title, item.originalFilename, item.category.rawValue, item.extractedText] + item.tags + names).joined(separator: " ")
            let reviewMatches = reviewFilter == .all || (reviewFilter == .unreviewed ? item.inbox : !item.inbox)
            let ocrMatches: Bool
            switch ocrFilter {
            case .all: ocrMatches = true
            case .complete: ocrMatches = item.ocrStatus == "complete"
            case .pending: ocrMatches = item.ocrStatus == "pending" || item.ocrStatus == "processing"
            case .failed: ocrMatches = item.ocrStatus == "failed"
            }
            let calendar = Calendar.current
            let day = calendar.startOfDay(for: item.captureDate)
            let dateMatches = !dateFilterEnabled || (day >= calendar.startOfDay(for: dateFrom) && day <= calendar.startOfDay(for: dateThrough))
            return inScope && reviewMatches && ocrMatches && dateMatches && (!favoritesOnly || item.favorite) && (tagFilter == nil || item.tags.contains { ContentTags.key($0) == ContentTags.key(tagFilter ?? "") }) && (categoryFilter == nil || item.category == categoryFilter) && (query.isEmpty || searchMatches?.contains(item.id) == true || text.localizedCaseInsensitiveContains(query))
        }.sorted { lhs, rhs in
            switch sort {
            case .newest: lhs.captureDate == rhs.captureDate ? lhs.id.uuidString < rhs.id.uuidString : lhs.captureDate > rhs.captureDate
            case .oldest: lhs.captureDate == rhs.captureDate ? lhs.id.uuidString < rhs.id.uuidString : lhs.captureDate < rhs.captureDate
            case .title: lhs.title == rhs.title ? lhs.id.uuidString < rhs.id.uuidString : lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        }
    }
    var dateGroups: [(title: String, items: [Screenshot])] {
        let values = visible
        if sort == .title { return [("By title", values)] }
        var groups: [(String, [Screenshot])] = []
        for item in values {
            let title: String
            if Calendar.current.isDateInToday(item.captureDate) { title = "Today" }
            else if Calendar.current.isDateInYesterday(item.captureDate) { title = "Yesterday" }
            else { title = item.captureDate.formatted(date: .abbreviated, time: .omitted) }
            if groups.last?.0 == title { groups[groups.count - 1].1.append(item) }
            else { groups.append((title, [item])) }
        }
        return groups
    }
    func markViewed(_ id: UUID) {
        guard !batchMode, items.first(where: { $0.id == id })?.inbox == true else { return }
        update(id) { $0.inbox = false }
    }
    func moveSelection(_ direction: MoveCommandDirection, columns: Int = 1) {
        guard !batchMode else { return }
        let values = visible
        guard !values.isEmpty else { return }
        guard let index = values.firstIndex(where: { $0.id == selectedID }) else {
            selectedID = values[0].id; return
        }
        let delta: Int
        switch direction {
        case .left: delta = -1
        case .right: delta = 1
        case .up: delta = -max(1, columns)
        case .down: delta = max(1, columns)
        @unknown default: return
        }
        selectedID = values[max(0, min(values.count - 1, index + delta))].id
    }
    func load() async {
        guard !didLoad else { return }; didLoad = true
        defer { loading = false }
        do {
            permissions = try await store.permissions()
            var failures: [String] = []
            for grant in permissions {
                do {
                    let refreshed = try await access.restore(grant)
                    try await store.save(refreshed)
                    if refreshed.isFolder { restoredSetupFolders.insert(refreshed.path) }
                } catch { failures.append(error.localizedDescription) }
            }
            if let saved = try await store.settings() { automation = saved }
            else {
                automation.watchedPaths = permissions.filter(\.isFolder).map(\.path)
                try await store.saveSettings(automation)
            }
            cleanupHistory = try await cleanup.recover()
            try await store.recoverProcessing()
            try await reload()
            if let saved = try await store.onboarding() {
                onboarding = saved; onboarding.step = max(0, min(2, saved.step))
            } else {
                onboarding.completed = !(try await store.needsOnboarding())
                onboarding.indexingEnabled = automation.indexingEnabled
                if onboarding.completed { onboarding.folderPath = automation.watchedPaths.first; onboarding.intakeEnabled = automation.intakeEnabled }
                try await store.saveOnboarding(onboarding)
            }
            showOnboarding = !onboarding.completed
            if showOnboarding, !failures.isEmpty { onboardingError = "Folder access needs to be renewed. Choose your screenshot folder again to reconnect it." }
            startAutomation()
            if !failures.isEmpty && !showOnboarding { error = failures.joined(separator: "\n") }
        } catch { self.error = error.localizedDescription }
    }
    func reload() async throws {
        await persistenceTask?.value
        await tagCatalogTask?.value
        let revision = editRevision
        let reviewRevision = groupReviewRevision
        let updatedItems = try await store.screenshots()
        let updatedCollections = try await store.collections().sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let updatedOperations = try await store.cleanupOperations()
        let updatedPermissions = try await store.permissions()
        let updatedTags = try await store.tagCatalog().names
        let rules = try await store.tagRules()
        let history = try await store.groupReviewHistory()
        guard revision == editRevision, reviewRevision == groupReviewRevision else { return }
        items = updatedItems; cleanupHistory = updatedOperations; collections = updatedCollections; permissions = updatedPermissions; customTags = updatedTags
        hiddenTags = rules.hiddenAutomatic.sorted(); currentTagRules = rules
        rebuildTagIndex()
        let groups = await Task.detached(priority: .utility) { Grouper.groups(updatedItems) }.value
        guard reviewRevision == groupReviewRevision else { return }
        automaticGroups = groups.filter { !automation.dismissedGroups.contains($0.id) && !history.suppresses($0) }
        reviewedGroupCount = history.decisions.count + automation.dismissedGroups.count
        if !query.isEmpty { scheduleSearch() }
    }
    var availableTags: [String] { tagNames }
    private func rebuildTagIndex() {
        let all = ContentTags.normalize(customTags + items.flatMap(\.tags))
        var counts: [String: Int] = [:]
        for item in items { for tag in ContentTags.normalize(item.tags) { counts[ContentTags.key(tag), default: 0] += 1 } }
        tagCounts = counts
        tagNames = all.sorted {
            let a = counts[ContentTags.key($0), default: 0], b = counts[ContentTags.key($1), default: 0]
            return a == b ? $0.localizedStandardCompare($1) == .orderedAscending : a > b
        }
    }
    func tagCount(_ name: String) -> Int { tagCounts[ContentTags.key(name), default: 0] }
    func addTag(_ name: String, to id: UUID) {
        update(id) { $0.tags = ContentTags.normalize($0.tags + [name]); $0.manualTags = true }
    }
    func removeTag(_ name: String, from id: UUID) {
        update(id) { $0.tags.removeAll { ContentTags.key($0) == ContentTags.key(name) }; $0.manualTags = true }
    }
    func createTag() {
        let name = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60, !name.contains(",") else { return }
        let resolved = currentTagRules.resolved(name)
        let existing = availableTags.first { ContentTags.key($0) == ContentTags.key(resolved) } ?? resolved
        editRevision += 1
        customTags = ContentTags.normalize(customTags + [existing])
        rebuildTagIndex()
        let catalog = TagCatalog(names: customTags)
        let previous = tagCatalogTask
        tagCatalogTask = Task {
            await previous?.value
            do { try await store.saveTagCatalog(catalog) } catch { self.error = error.localizedDescription }
        }
        if applyNewTagToSelection, let id = selectedID { addTag(existing, to: id) }
        newTagName = ""; showNewTag = false
    }
    func renameTag(_ old: String, to raw: String) {
        guard !tagManagementBusy else { return }
        let target = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        tagManagementBusy = true
        Task {
            defer { tagManagementBusy = false }
            do {
                await persistenceTask?.value; await tagCatalogTask?.value
                try await store.renameTag(old, to: target)
                if let tagFilter, ContentTags.key(tagFilter) == ContentTags.key(old) { self.tagFilter = target }
                try await reload()
                notice = "Tag updated throughout your library"
            } catch { self.error = error.localizedDescription }
        }
    }
    func hideTag(_ tag: String) {
        guard !tagManagementBusy else { return }; tagManagementBusy = true
        Task {
            defer { tagManagementBusy = false }
            do {
                await persistenceTask?.value; await tagCatalogTask?.value
                try await store.hideAutomaticTag(tag)
                if tagFilter == tag { tagFilter = nil }
                try await reload()
            } catch { self.error = error.localizedDescription }
        }
    }
    func restoreTag(_ tag: String) {
        guard !tagManagementBusy else { return }; tagManagementBusy = true
        Task {
            defer { tagManagementBusy = false }
            do { try await store.restoreAutomaticTag(tag); try await reload() }
            catch { self.error = error.localizedDescription }
        }
    }
    func scheduleSearch() {
        searchTask?.cancel(); searchMatches = nil
        let text = query
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        searchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(250))
                let ids = try await store.searchIDs(text)
                guard !Task.isCancelled, query == text else { return }
                searchMatches = ids
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
    var pendingCount: Int { items.filter { $0.ocrStatus == "pending" || $0.ocrStatus == "processing" || ($0.ocrStatus == "complete" && ($0.taggingVersion ?? 0) < ContentTags.version) }.count }
    func startAutomation() {
        guard onboarding.completed else { watchStatus = "Finish setup to start automatic intake"; return }
        guard watchTask == nil else { return }
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !automation.intakeEnabled {
                    watchStatus = "Automatic intake paused"
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }; continue
                }
                if cleanupBusy { do { try await Task.sleep(for: .seconds(1)) } catch { return }; continue }
                let report = await watcher.reconcile(paths: automation.watchedPaths)
                watchStatus = report.errors.first ?? (automation.watchedPaths.isEmpty ? "Automatic intake is off" : "Watching \(automation.watchedPaths.count) folder\(automation.watchedPaths.count == 1 ? "" : "s")")
                if report.imported > 0 {
                    notice = "\(report.imported) new or updated screenshots gathered automatically"
                    do { try await reload() } catch { self.error = error.localizedDescription }
                }
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
        indexingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                var processed = false
                if automation.indexingEnabled && !cleanupBusy {
                    do {
                        processed = try await ocr.processNext()
                        if processed { try await reload() }
                        indexingStatus = pendingCount > 0 ? "Organizing \(pendingCount) screenshots…" : "Library organized"
                    } catch { indexingStatus = error.localizedDescription }
                } else { indexingStatus = "Automatic organization paused" }
                do { try await Task.sleep(for: processed ? .milliseconds(150) : .seconds(2)) } catch { return }
            }
        }
    }
    func setIntakeEnabled(_ enabled: Bool) {
        automation.intakeEnabled = enabled
        watchStatus = enabled ? "Resuming automatic intake…" : "Automatic intake paused"
        saveAutomation()
    }
    func saveAutomation() {
        let settings = automation
        let previous = settingsTask
        settingsTask = Task {
            await previous?.value
            do { try await store.saveSettings(settings) } catch { self.error = error.localizedDescription }
        }
    }
    func chooseWatchFolder() {
        let panel = NSOpenPanel(); panel.title = "Watch Screenshot Folder"; panel.prompt = "Watch Folder"
        panel.message = "New screenshots in this folder will be imported and organized locally while Gather is running, including with its window closed. Existing screenshots will also be gathered. Files stay in place."
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await grant(url, folder: true)
                if !automation.watchedPaths.contains(url.path) { automation.watchedPaths.append(url.path) }
                try await store.saveSettings(automation); try await reload()
            } catch { self.error = error.localizedDescription }
        }
    }
    func stopWatching(_ path: String) {
        automation.watchedPaths.removeAll { $0 == path }; saveAutomation()
    }
    func retryOCR(_ id: UUID) {
        Task {
            do { try await store.setProcessing(id, status: "pending"); try await reload() }
            catch { self.error = error.localizedDescription }
        }
    }
    func dismissGroup(_ group: AutomaticGroup) {
        guard !groupReviewBusy else { return }; groupReviewBusy = true; groupReviewRevision += 1
        groupDecisionTask = Task {
            defer { groupReviewBusy = false }
            do {
                try await store.dismissSuggestion(group)
                reviewGroup = nil
                if scope == .related(group.id) { scope = .all }
                try await reload()
                notice = "Group dismissed. Overlapping suggestions will stay hidden."
            } catch { self.error = error.localizedDescription }
        }
    }
    func keepGroup(_ group: AutomaticGroup) { reviewGroup = group }
    func saveReviewedGroup(_ group: AutomaticGroup, name: String, includedIDs: Set<UUID>) {
        guard !groupReviewBusy else { return }; groupReviewBusy = true; groupReviewRevision += 1
        groupDecisionTask = Task {
            defer { groupReviewBusy = false }
            do {
                await persistenceTask?.value
                let collection = GatherCore.Collection(name: name)
                try await store.acceptGroup(group, collection: collection, includedIDs: includedIDs)
                reviewGroup = nil
                try await reload(); scope = .collection(collection.id); tagFilter = nil; categoryFilter = nil
                notice = "Saved \(includedIDs.count) screenshots as “\(name.trimmingCharacters(in: .whitespacesAndNewlines))”"
            } catch { self.error = error.localizedDescription }
        }
    }
    func resetGroupReviews() {
        guard !groupReviewBusy else { return }; groupReviewBusy = true; groupReviewRevision += 1
        groupDecisionTask = Task {
            defer { groupReviewBusy = false }
            do {
                await settingsTask?.value
                var settings = automation; settings.dismissedGroups.removeAll()
                try await store.resetGroupReviews(settings: settings)
                automation = settings
                try await reload()
                notice = "Group review history reset. Existing collections are unchanged."
            } catch { self.error = error.localizedDescription }
        }
    }
    func grant(_ url: URL, folder: Bool) async throws {
        let bookmark = try await access.grant(url, isFolder: folder)
        try await store.save(bookmark)
        if folder { restoredSetupFolders.insert(url.path) }
    }
    func chooseFiles() {
        guard !busy && !cleanupBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "Import Screenshots"; panel.prompt = "Import"
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .webP]
        guard panel.runModal() == .OK else { return }
        importURLs(panel.urls)
    }
    func chooseFolder() {
        guard !busy && !cleanupBusy else { return }
        let panel = NSOpenPanel()
        panel.title = "Scan a Screenshot Folder"; panel.prompt = "Scan"
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.message = "Gather looks for screenshot filenames and metadata. You’ll review the count before importing. Originals stay in place."
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        scanFolder(folder)
    }
    func scanFolder(_ folder: URL) {
        guard !busy && !cleanupBusy else { return }
        busy = true; progress = "Scanning folder…"
        Task {
            defer { busy = false; progress = "" }
            do {
                try await grant(folder, folder: true)
                let urls = try await Task.detached { try ImageService.candidates(in: folder, screenshotsOnly: true) }.value
                pendingScan = Scan(folder: folder, urls: urls)
            } catch { self.error = error.localizedDescription }
        }
    }
    func acceptDrop(_ urls: [URL]) -> Bool {
        guard !busy && !cleanupBusy else { return false }
        let folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        if let folder = folders.first {
            guard urls.count == 1 else {
                error = "Drop images together, or scan one folder at a time."
                return false
            }
            scanFolder(folder)
        } else { importURLs(urls) }
        return true
    }
    func importURLs(_ urls: [URL], authorizedFolder: URL? = nil) {
        guard !busy && !cleanupBusy else { return }
        busy = true; progress = "Preparing import…"
        Task {
            defer { busy = false; progress = "" }
            var images: [URL] = []
            var failures: [String] = []
            for url in urls {
                do {
                    if authorizedFolder != nil { images.append(url); continue }
                    let isFolder = (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true
                    try await grant(url, folder: isFolder)
                    if isFolder {
                        let found = try await Task.detached { try ImageService.candidates(in: url, screenshotsOnly: true) }.value
                        images.append(contentsOf: found)
                    } else if ImageService.isImage(url) { images.append(url) }
                    else { failures.append("\(url.lastPathComponent): Unsupported image format") }
                } catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            let report = await importer.run(urls: images, sourceFolder: authorizedFolder?.path) { [weak self] done, total in
                await MainActor.run { self?.progress = "Importing \(done) of \(total)…" }
            }
            do { try await reload() } catch { failures.append(error.localizedDescription) }
            notice = "\(report.imported) imported · \(report.unchanged) already in library"
            failures += report.errors
            if !failures.isEmpty { self.error = failures.joined(separator: "\n") }
        }
    }
    func update(_ id: UUID, change: (inout Screenshot) -> Void) {
        guard !batchBusy else { return }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        editRevision += 1
        var item = items[index]; change(&item)
        item.tags = currentTagRules.apply(item.tags, automatic: !item.manualTags)
        items[index] = item
        rebuildTagIndex()
        let previous = persistenceTask
        persistenceTask = Task {
            await previous?.value
            do { try await store.updateMetadata(item) }
            catch { self.error = error.localizedDescription; try? await reload() }
        }
    }
    func createCollection() {
        let name = collectionName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task {
            do {
                let collection = GatherCore.Collection(name: name)
                try await store.save(collection); try await reload(); scope = .collection(collection.id)
                collectionName = ""
            } catch { self.error = error.localizedDescription }
        }
    }
    func grantAgain() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true
        panel.message = "Select the original file or its containing folder to restore access."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                let isFolder = (try url.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true
                try await grant(url, folder: isFolder)
                try await reload()
                // Recreate image views so they retry after permission changes.
                selectedID = nil
                notice = "Access refreshed. Select the screenshot again."
            } catch { self.error = error.localizedDescription }
        }
    }
    func locate(_ item: Screenshot) {
        let panel = NSOpenPanel()
        panel.title = "Locate Original Screenshot"
        panel.message = "Choose the original image. Gather checks its content hash before updating the reference."
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .webP]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await grant(url, folder: false)
                let hash = try await Task.detached { try ImageService.hash(url) }.value
                guard hash == item.contentHash else {
                    error = "This image does not match the original screenshot. Choose the original or an identical copy."
                    return
                }
                await persistenceTask?.value
                var relocated = item
                relocated.path = url.standardizedFileURL.path
                try await store.update(relocated)
                try await reload()
                selectedID = nil
                notice = "Original located. Select the screenshot to refresh the preview."
            } catch { self.error = error.localizedDescription }
        }
    }
    var visibleBatchIDs: Set<UUID> { batchSelection.intersection(visible.map(\.id)) }
    func toggleBatchSelection(_ id: UUID) {
        if !batchSelection.insert(id).inserted { batchSelection.remove(id) }
    }
    func endBatchSelection() { batchMode = false; batchSelection = [] }
    func applyBatch(_ action: BatchAction) {
        let ids = visibleBatchIDs
        guard !ids.isEmpty, !batchBusy else { return }
        batchBusy = true; editRevision += 1
        batchTask = Task {
            defer { batchBusy = false }
            do {
                await persistenceTask?.value; await tagCatalogTask?.value
                try await store.applyBatch(ids: ids, action: action)
                try await reload()
                batchSelection.formIntersection(visible.map(\.id))
                showBatchTags = false
                notice = "Updated \(ids.count) screenshots"
            } catch { self.error = error.localizedDescription }
        }
    }
    var setupFolderReady: Bool {
        guard let path = onboarding.folderPath, restoredSetupFolders.contains(path),
              FileManager.default.isReadableFile(atPath: path) else { return false }
        return (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
    func reviewSetup() {
        guard !loading, !onboardingBusy else { return }
        onboarding.step = 0; onboarding.folderPath = automation.watchedPaths.first
        onboarding.intakeEnabled = automation.intakeEnabled; onboarding.indexingEnabled = automation.indexingEnabled
        AppSession.shared.loginItem.refresh()
        onboarding.launchAtLogin = AppSession.shared.loginItem.registered
        onboardingError = nil; showOnboarding = true
    }
    func saveSetupProgress() {
        guard !onboardingBusy else { return }
        let draft = onboarding, previous = onboardingTask
        onboardingTask = Task {
            await previous?.value
            do { try await store.saveOnboarding(draft) }
            catch { onboardingError = error.localizedDescription }
        }
    }
    func chooseSetupFolder() {
        guard !onboardingBusy else { return }
        let panel = NSOpenPanel(); panel.title = "Choose Your Screenshot Folder"; panel.prompt = "Allow Folder"
        panel.message = "Gather reads screenshot images in this folder to import existing and new captures. Your files stay in place. macOS may also ask permission to access Desktop or Documents."
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.directoryURL = onboarding.folderPath.map { URL(fileURLWithPath: $0) } ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        onboardingBusy = true; onboardingError = nil
        let previous = onboardingTask
        onboardingTask = Task {
            await previous?.value
            defer { onboardingBusy = false }
            do {
                try await grant(folder, folder: true)
                guard FileManager.default.isReadableFile(atPath: folder.path) else { throw LibraryError.permission(folder.path) }
                onboarding.folderPath = folder.path; onboarding.intakeEnabled = true
                try await store.saveOnboarding(onboarding)
            } catch { onboardingError = "Gather could not read that folder. Choose it again to allow access, try a different folder, or use manual import.\n\(error.localizedDescription)" }
        }
    }
    func finishSetup(manual: Bool = false) {
        guard !onboardingBusy else { return }
        onboardingBusy = true; onboardingError = nil
        let previous = onboardingTask
        onboardingTask = Task {
            await previous?.value; await settingsTask?.value
            defer { onboardingBusy = false }
            do {
                var settings = automation
                if manual { onboarding.folderPath = nil; onboarding.intakeEnabled = false }
                if let path = onboarding.folderPath {
                    guard setupFolderReady else { throw LibraryError.permission(path) }
                    if !settings.watchedPaths.contains(path) { settings.watchedPaths.append(path) }
                }
                settings.intakeEnabled = !manual && setupFolderReady && onboarding.intakeEnabled
                settings.indexingEnabled = onboarding.indexingEnabled
                try await store.finishOnboarding(onboarding, settings: settings)
                onboarding.completed = true; onboarding.step = 2; automation = settings
                showOnboarding = false; startAutomation()
                notice = settings.intakeEnabled ? "You’re ready. Gathering screenshots from your chosen folder…" : "You’re ready. Import screenshots whenever you like."
            } catch { onboardingError = error.localizedDescription }
        }
    }
    func dragProvider(_ item: Screenshot) -> NSItemProvider {
        guard !cleanupBusy else { notice = "Wait for the file operation to finish before dragging."; return NSItemProvider() }
        let latest = items.first { $0.id == item.id } ?? item
        return DragFileProvider.make(item: latest, directory: dragDirectory) { [weak self] message in
            Task { @MainActor in self?.error = "Could not share this image. It may need file access or its original may be unavailable.\n\(message)" }
        }
    }
    func openImage(_ item: Screenshot) {
        selectedID = item.id
        markViewed(item.id)
        imagePreview = item
    }
    func openOrganizer() {
        guard !busy && !cleanupBusy else { return }
        cleanupPreview = nil; showOrganizer = true
    }
    private func authorizeSourceFolders(_ paths: [String]) async throws {
        let folders = Set(paths.map { URL(fileURLWithPath: $0).deletingLastPathComponent().resolvingSymlinksInPath().path })
        let grants = try await store.permissions().filter(\.isFolder)
        for folder in folders.sorted() {
            let authorized = grants.contains {
                let root = URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path
                return folder == root || folder.hasPrefix(root + "/")
            }
            if authorized { continue }
            let panel = NSOpenPanel(); panel.title = "Allow Moving and Undo"
            panel.message = "Select \(folder) so Gather can move the chosen screenshots and restore them here during undo."
            panel.prompt = "Allow Folder"; panel.canChooseFiles = false; panel.canChooseDirectories = true
            panel.directoryURL = URL(fileURLWithPath: folder)
            guard panel.runModal() == .OK, let url = panel.url else { throw CocoaError(.userCancelled) }
            guard url.resolvingSymlinksInPath().path == folder else { throw CleanupError.problem("Choose the original containing folder: \(folder)") }
            try await grant(url, folder: true)
        }
    }
    func chooseCleanupDestination(ids: Set<UUID>) {
        guard !ids.isEmpty, !cleanupBusy, !busy else { return }
        let panel = NSOpenPanel(); panel.title = "Choose Screenshot Destination"; panel.prompt = "Preview Moves"
        panel.message = "Choose where these screenshots should move. You will review every source and destination before anything moves."
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        cleanupBusy = true; cleanupStatus = "Preparing move preview…"
        cleanupTask = Task {
            defer { cleanupBusy = false }
            do {
                await persistenceTask?.value
                try await grant(destination, folder: true)
                let paths = items.filter { ids.contains($0.id) }.map(\.path)
                try await authorizeSourceFolders(paths)
                cleanupPreview = try await cleanup.plan(ids: ids, destination: destination)
                try await reload()
            } catch let failure as CocoaError where failure.code == .userCancelled { notice = "Move preview cancelled" }
            catch { self.error = error.localizedDescription }
        }
    }
    func performCleanup() {
        guard let plan = cleanupPreview, !cleanupBusy else { return }
        cleanupBusy = true; cleanupStatus = "Moving screenshots…"
        cleanupTask = Task {
            defer { cleanupBusy = false }
            do {
                await persistenceTask?.value
                cleanupPreview = try await cleanup.execute(plan) { [weak self] done, total in
                    await MainActor.run { self?.cleanupStatus = "Moving \(done) of \(total)…" }
                }
                await watcher.reset(); try await reload()
                notice = "File operation finished. Review the per-file results."
            } catch { self.error = error.localizedDescription; try? await reload() }
        }
    }
    func undoCleanup(_ id: UUID) {
        guard !cleanupBusy else { return }; cleanupBusy = true; cleanupStatus = "Restoring screenshots…"
        cleanupTask = Task {
            defer { cleanupBusy = false }
            do {
                await persistenceTask?.value
                if let operation = try await store.cleanupOperation(id) {
                    try await authorizeSourceFolders(operation.entries.filter(\.canUndo).flatMap { [$0.originalPath, $0.destinationPath] })
                }
                let result = try await cleanup.undo(id) { [weak self] done, total in
                    await MainActor.run { self?.cleanupStatus = "Restoring \(done) of \(total)…" }
                }
                if cleanupPreview?.id == id { cleanupPreview = result }
                await watcher.reset(); try await reload()
                notice = "Undo finished. Review the per-file results."
            } catch { self.error = error.localizedDescription; try? await reload() }
        }
    }
    func recoverCleanup() {
        guard !cleanupBusy else { return }; cleanupBusy = true; cleanupStatus = "Checking interrupted operations…"
        cleanupTask = Task {
            defer { cleanupBusy = false }
            do { cleanupHistory = try await cleanup.recover(); await watcher.reset(); try await reload() }
            catch { self.error = error.localizedDescription }
        }
    }
    func finishPendingEdits() async {
        watchTask?.cancel(); indexingTask?.cancel(); searchTask?.cancel()
        await onboardingTask?.value
        await batchTask?.value
        await cleanupTask?.value
        await groupDecisionTask?.value
        await settingsTask?.value
        await tagCatalogTask?.value
        try? await store.saveSettings(automation)
        await persistenceTask?.value
        await access.releaseAll()
    }
    func showInFinder(_ item: Screenshot) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)]) }
}
