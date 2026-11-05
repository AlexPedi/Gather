import Foundation
import CoreText
import CoreGraphics
import ImageIO
import GatherCore
import CSQLite

extension LibraryChecks {
    public func testClassificationAndGrouping() throws {
        try checkEqual(Classifier.suggest(text: "Annual insurance benefits\nPremium deductible copay coverage").category, .finance)
        try checkEqual(Classifier.suggest(text: "Hotel reservation\nFlight departure airport booking").category, .travel)
        try checkEqual(Classifier.suggest(text: "tax").category, .uncategorized)
        try checkEqual(Classifier.suggest(text: "").title, nil)
        try checkEqual(Classifier.suggest(text: "Lorem ipsum neutral content").category, .uncategorized)
        func item(_ index: Int, text: String, seconds: Double = 0) -> Screenshot {
            var value = Screenshot(path: "/test/\(index).png", sourceFolder: "/test", captureDate: Date(timeIntervalSince1970: seconds), fileSize: 50, width: 30, height: 30, contentHash: "hash-\(index)")
            value.extractedText = text; value.ocrStatus = "complete"; value.category = .finance
            return value
        }
        let a = item(1, text: "insurance benefits deductible coverage annual premium", seconds: 1)
        let b = item(2, text: "insurance benefits deductible coverage annual copay", seconds: 60)
        let unrelated = item(3, text: "hotel booking departure flight airport reservation", seconds: 65)
        let distant = item(4, text: a.extractedText, seconds: 100_000)
        let groups = Grouper.groups([a,b,unrelated,distant])
        try checkEqual(groups.count, 1)
        try checkEqual(Set(groups[0].itemIDs), Set([a.id,b.id]))
        var duplicate = distant; duplicate.contentHash = a.contentHash
        try checkTrue(Grouper.groups([a,duplicate]).contains { $0.title == "Exact duplicates" })
    }
    public func testOCRMergeSearchAndRestart() async throws {
        let root = try temporary(); let store = try LibraryStore(url: root.appendingPathComponent("db.sqlite"))
        let file = root.appendingPathComponent("Screenshot.png"); try image(at: file)
        var original = try ImageService.inspect(file, sourceFolder: root.path)
        try await store.insert(original)
        let text = "Annual insurance benefits\nPremium deductible copay coverage"
        try await store.completeOCR(original.id, hash: original.contentHash, text: text)
        original.favorite = true // A UI snapshot that predates OCR completion.
        try await store.updateMetadata(original)
        var latest = try unwrap(try await store.record(original.id))
        try checkEqual(latest.category, .finance); try checkEqual(latest.extractedText, text)
        try checkTrue(latest.favorite)
        let matches = try await store.searchIDs("deductible coverage")
        try checkTrue(matches.contains(original.id))
        latest.title = "My manual title"; latest.manualTitle = true; latest.category = .work; latest.manualCategory = true
        latest.tags = ["Keep"]; latest.manualTags = true
        try await store.updateMetadata(latest)
        try await store.completeOCR(latest.id, hash: latest.contentHash, text: "Hotel reservation airport flight")
        let preserved = try unwrap(try await store.record(latest.id))
        try checkEqual(preserved.title, "My manual title"); try checkEqual(preserved.category, .work); try checkEqual(preserved.tags, ["Keep"])
        let oldMatches = try await store.searchIDs("deductible")
        try checkFalse(oldMatches.contains(original.id))
        let manualMatches = try await store.searchIDs("manual")
        try checkTrue(manualMatches.contains(original.id))
        try await store.setProcessing(original.id, status: "processing")
        let reopened = try LibraryStore(url: root.appendingPathComponent("db.sqlite"))
        try await reopened.recoverProcessing()
        let pending = try await reopened.nextPending()
        try checkEqual(pending?.id, original.id)
        var settings = AutomationSettings(); settings.watchedPaths = [root.path]; settings.dismissedGroups = ["dismissed"]
        try await store.saveSettings(settings)
        let savedSettings = try await reopened.settings()
        try checkEqual(savedSettings?.watchedPaths, [root.path]); try checkEqual(savedSettings?.dismissedGroups, ["dismissed"])
    }
    public func testWatchingStabilityAndReconciliation() async throws {
        var gate = StabilityGate()
        let a = FileStamp(size: 10, modified: Date(timeIntervalSince1970: 1))
        try checkTrue(gate.ready(["file": a]).isEmpty)
        try checkEqual(gate.ready(["file": a]), ["file"])
        gate.mark("file", stamp: a)
        try checkTrue(gate.ready(["file": a]).isEmpty)
        let b = FileStamp(size: 20, modified: Date(timeIntervalSince1970: 2))
        try checkTrue(gate.ready(["file": b]).isEmpty)
        try checkEqual(gate.ready(["file": b]), ["file"])
        let root = try temporary(); let store = try LibraryStore(url: root.appendingPathComponent("db.sqlite"))
        let watcher = FolderWatcher(importer: Importer(store: store))
        let file = root.appendingPathComponent("Screenshot 1.png"); try image(at: file)
        let first = await watcher.reconcile(paths: [root.path]); try checkEqual(first.imported, 0)
        let second = await watcher.reconcile(paths: [root.path]); try checkEqual(second.imported, 1)
        let third = await watcher.reconcile(paths: [root.path]); try checkEqual(third.imported, 0)
        let records = try await store.screenshots(); try checkEqual(records.count, 1)
        let restarted = FolderWatcher(importer: Importer(store: store))
        _ = await restarted.reconcile(paths: [root.path]); _ = await restarted.reconcile(paths: [root.path])
        let after = try await store.screenshots(); try checkEqual(after.count, 1)
        var manual = try unwrap(after.first); manual.title = "Keep my correction"; manual.manualTitle = true
        try await store.updateMetadata(manual)
        try createOCRFixture(at: file)
        _ = await watcher.reconcile(paths: [root.path]); _ = await watcher.reconcile(paths: [root.path])
        let changed = try unwrap(try await store.record(manual.id))
        try checkEqual(changed.title, "Keep my correction"); try checkEqual(changed.ocrStatus, "pending")
        try checkFalse(changed.contentHash == manual.contentHash)
    }
    public func testDynamicAndCustomTags() async throws {
        let text = "The astronomer uses a telescope in the observatory. The telescope reveals a nebula. The nebula fills the observatory display."
        let tags = ContentTags.suggest(text)
        try checkFalse(tags.isEmpty)
        try checkTrue(tags.contains { ContentTags.key($0).contains("telescope") || ContentTags.key($0).contains("nebula") })
        try checkEqual(ContentTags.suggest(""), [])
        try checkEqual(ContentTags.normalize([" Research ", "research", "RESEARCH", "Client launch"]), ["Research", "Client launch"])
        let root = try temporary(); let db = root.appendingPathComponent("tags.sqlite")
        let store = try LibraryStore(url: db)
        var legacy = Screenshot(path: "/not-needed-for-retagging.png", sourceFolder: "/", captureDate: Date(), fileSize: 20, width: 20, height: 20, contentHash: "retag")
        legacy.ocrStatus = "complete"; legacy.extractedText = text; legacy.tags = ["Old rule tag"]
        try await store.insert(legacy)
        let worker = OCRWorker(store: store)
        _ = try await worker.processNext()
        var refreshed = try unwrap(try await store.record(legacy.id))
        try checkEqual(refreshed.taggingVersion, ContentTags.version); try checkFalse(refreshed.tags.contains("Old rule tag"))
        refreshed.tags = ["Client launch"]; refreshed.manualTags = true
        try await store.updateMetadata(refreshed)
        try await store.completeTags(refreshed.id, hash: refreshed.contentHash, tags: ["Replacement"])
        let preserved = try unwrap(try await store.record(refreshed.id))
        try checkEqual(preserved.tags, ["Client launch"])
        try await store.saveTagCatalog(TagCatalog(names: ["Client launch", "Not yet assigned"]))
        let reopened = try LibraryStore(url: db)
        let catalog = try await reopened.tagCatalog()
        try checkEqual(catalog.names, ["Client launch", "Not yet assigned"])
        let matches = try await reopened.searchIDs("Client launch")
        try checkTrue(matches.contains(legacy.id))
    }
    public func testTagQualityAndManagement() async throws {
        try checkEqual(ContentTags.nounStem("Children"), "child")
        let suggestions = ContentTags.suggest("Edit Share Attach Login. Children and a child study telescopes. The telescope reveals galaxies and a galaxy. Telescopes reveal galaxies.")
        try checkFalse(suggestions.contains { ["edit", "share", "attach", "login"].contains(ContentTags.key($0)) })
        try checkTrue(suggestions.contains { ContentTags.key($0) == "telescope" })
        try checkFalse(suggestions.contains { ContentTags.key($0) == "telescopes" })
        let root = try temporary(); let db = root.appendingPathComponent("management.sqlite")
        let store = try LibraryStore(url: db)
        var a = Screenshot(path: "/a.png", sourceFolder: "/", captureDate: Date(), fileSize: 20, width: 20, height: 20, contentHash: "a")
        a.tags = ["Children", "Research"]; a.manualTags = true; a.ocrStatus = "complete"
        var b = Screenshot(path: "/b.png", sourceFolder: "/", captureDate: Date(), fileSize: 20, width: 20, height: 20, contentHash: "b")
        b.tags = ["Children", "Research"]; b.ocrStatus = "complete"
        try await store.insert(a); try await store.insert(b)
        try await store.saveTagCatalog(TagCatalog(names: ["Children", "Research", "Unused"]))
        try await store.renameTag("Children", to: "Family")
        let renamed = try unwrap(try await store.record(a.id))
        try checkEqual(renamed.tags, ["Family", "Research"]); try checkTrue(renamed.manualTags)
        let matches = try await store.searchIDs("Family"); try checkTrue(matches.contains(a.id))
        try await store.completeTags(b.id, hash: b.contentHash, tags: ["Children", "Research"])
        let future = try unwrap(try await store.record(b.id)); try checkEqual(future.tags, ["Family", "Research"])
        // A stale manual save cannot resurrect a renamed tag.
        a.favorite = true; try await store.updateMetadata(a)
        let staleMerged = try unwrap(try await store.record(a.id)); try checkEqual(staleMerged.tags, ["Family", "Research"])
        try await store.renameTag("Family", to: "Research")
        let merged = try unwrap(try await store.record(a.id)); try checkEqual(merged.tags, ["Research"])
        try await store.renameTag("Research", to: "RESEARCH")
        let cased = try unwrap(try await store.record(a.id)); try checkEqual(cased.tags, ["RESEARCH"])
        try await store.hideAutomaticTag("RESEARCH")
        let hiddenAuto = try unwrap(try await store.record(b.id)); try checkEqual(hiddenAuto.tags, [])
        let keptManual = try unwrap(try await store.record(a.id)); try checkEqual(keptManual.tags, ["RESEARCH"])
        try await store.completeTags(b.id, hash: b.contentHash, tags: ["Children", "Research"])
        let stillHidden = try unwrap(try await store.record(b.id)); try checkEqual(stillHidden.tags, [])
        let reopened = try LibraryStore(url: db)
        let rules = try await reopened.tagRules(); try checkTrue(rules.hiddenAutomatic.contains("research"))
        try await reopened.restoreAutomaticTag("research")
        try await reopened.completeTags(b.id, hash: b.contentHash, tags: ["Children"])
        let restored = try unwrap(try await reopened.record(b.id)); try checkEqual(restored.tags, ["RESEARCH"])
        let catalog = try await reopened.tagCatalog(); try checkEqual(catalog.names, ["RESEARCH", "Unused"])
        // Reversing a rename must not form an alias cycle.
        try await reopened.renameTag("RESEARCH", to: "Children")
        let reverse = try await reopened.tagRules(); try checkEqual(reverse.resolved("Research"), "Children")
    }
    public func testLegacyMigration() async throws {
        let root = try temporary(); let file = root.appendingPathComponent("Screenshot legacy.png"); try image(at: file)
        var legacy = try ImageService.inspect(file, sourceFolder: root.path)
        legacy.title = "Legacy manual title"; legacy.manualTitle = true; legacy.favorite = true
        let dbURL = root.appendingPathComponent("legacy.sqlite")
        do {
            var db: OpaquePointer?
            try checkEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
            defer { sqlite3_close(db) }
            try checkEqual(sqlite3_exec(db, "CREATE TABLE screenshots(id TEXT PRIMARY KEY,path TEXT NOT NULL UNIQUE,hash TEXT NOT NULL,payload BLOB NOT NULL); CREATE TABLE collections(id TEXT PRIMARY KEY,payload BLOB NOT NULL); CREATE TABLE access(path TEXT PRIMARY KEY,payload BLOB NOT NULL); PRAGMA user_version=1;", nil, nil, nil), SQLITE_OK)
            var stmt: OpaquePointer?
            try checkEqual(sqlite3_prepare_v2(db, "INSERT INTO screenshots VALUES(?,?,?,?)", -1, &stmt, nil), SQLITE_OK)
            defer { sqlite3_finalize(stmt) }
            for (offset, value) in [legacy.id.uuidString, legacy.path, legacy.contentHash].enumerated() {
                _ = value.withCString { sqlite3_bind_text(stmt, Int32(offset + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            }
            let data = try JSONEncoder().encode(legacy)
            _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, 4, $0.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            try checkEqual(sqlite3_step(stmt), SQLITE_DONE)
        }
        let store = try LibraryStore(url: dbURL)
        let migrated = try unwrap(try await store.record(legacy.id))
        try checkEqual(migrated.title, legacy.title); try checkTrue(migrated.favorite)
        let pending = try await store.nextPending(); try checkEqual(pending?.id, legacy.id)
        let matches = try await store.searchIDs("Legacy"); try checkTrue(matches.contains(legacy.id))
    }
    public func createOCRFixture(at file: URL, extraLine: String? = nil) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let context = try unwrap(CGContext(data: nil, width: 1600, height: 500, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1600, height: 500))
        let font = CTFontCreateWithName("Helvetica" as CFString, 48, nil)
        let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)]
        let lines = ["Hotel reservation confirmation", "Flight departure airport booking"] + (extraLine.map { [$0] } ?? [])
        for (index, text) in lines.enumerated() {
            context.textPosition = CGPoint(x: 60, y: 340 - index * 85)
            CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)), context)
        }
        let destination = try unwrap(CGImageDestinationCreateWithURL(file as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try unwrap(context.makeImage()), nil); try checkTrue(CGImageDestinationFinalize(destination))
    }
    public func testVisionOCR() async throws {
        let root = try temporary(); let file = root.appendingPathComponent("Screenshot text.png")
        try createOCRFixture(at: file)
        let text = try await Task.detached { try OCRWorker.recognize(file) }.value
        try checkTrue(text.lowercased().contains("reservation"))
        try checkEqual(Classifier.suggest(text: text).category, .travel)
        let store = try LibraryStore(url: root.appendingPathComponent("db.sqlite"))
        let missing = Screenshot(path: root.appendingPathComponent("missing.png").path, sourceFolder: root.path, captureDate: Date(), fileSize: 50, width: 10, height: 10, contentHash: "missing")
        try await store.insert(missing)
        let valid = try ImageService.inspect(file, sourceFolder: root.path); try await store.insert(valid)
        let worker = OCRWorker(store: store)
        _ = try await worker.processNext(); _ = try await worker.processNext()
        let failed = try await store.record(missing.id); let completed = try await store.record(valid.id)
        try checkEqual(failed?.ocrStatus, "failed"); try checkEqual(completed?.ocrStatus, "complete")
        let matches = try await store.searchIDs("reservation"); try checkTrue(matches.contains(valid.id))
    }
}
