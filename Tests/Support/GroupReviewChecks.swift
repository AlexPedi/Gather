import Foundation
import CSQLite
import GatherCore

extension LibraryChecks {
    private func groupItem(_ root: URL, number: Int) -> Screenshot {
        var item = Screenshot(path: root.appendingPathComponent("\(number).png").path, sourceFolder: root.path,
                              captureDate: Date(timeIntervalSince1970: Double(number * 60)), fileSize: 50, width: 50, height: 50,
                              contentHash: "unique-\(number)")
        item.extractedText = "insurance benefits deductible coverage annual premium"
        item.category = .finance; item.ocrStatus = "complete"; item.taggingVersion = ContentTags.version
        return item
    }
    public func testGroupReviewSelectionAndMemory() async throws {
        let root = try temporary(); let db = root.appendingPathComponent("review.sqlite")
        let store = try LibraryStore(url: db)
        var a = groupItem(root, number: 1); a.title = "My correction"; a.manualTitle = true; a.favorite = true
        let b = groupItem(root, number: 2), excluded = groupItem(root, number: 3)
        for item in [a,b,excluded] { try await store.insert(item) }
        let group = try unwrap(Grouper.groups([a,b,excluded]).first)
        try checkEqual(group.kind, .related); try checkFalse(group.evidence.isEmpty)
        try checkTrue(group.evidence.allSatisfy { $0.similarity >= 0.22 && $0.captureGap <= 45 * 60 })
        try checkTrue(group.sharedWords.contains("coverage"))
        let collection = Collection(name: "  Benefit comparisons  ")
        try await store.acceptGroup(group, collection: collection, includedIDs: [a.id,b.id])
        let saved = try await store.collections(); try checkEqual(saved.first?.name, "Benefit comparisons")
        let updatedA = try unwrap(try await store.record(a.id)); let updatedB = try unwrap(try await store.record(b.id))
        let untouched = try unwrap(try await store.record(excluded.id))
        try checkEqual(updatedA.collections, [collection.id]); try checkEqual(updatedB.collections, [collection.id]); try checkEqual(untouched.collections, [])
        try checkEqual(updatedA.title, a.title); try checkTrue(updatedA.manualTitle); try checkTrue(updatedA.favorite)
        try checkEqual(updatedA.path, a.path); try checkEqual(updatedA.extractedText, a.extractedText)
        let matches = try await store.searchIDs("Benefit comparisons")
        try checkEqual(matches, Set([a.id,b.id]))
        let reopened = try LibraryStore(url: db)
        let history = try await reopened.groupReviewHistory()
        try checkTrue(history.suppresses(group)); try checkEqual(history.decisions.first?.collectionID, collection.id)
        let smallChange = AutomaticGroup(id: "grown", title: group.title, reason: group.reason,
                                         itemIDs: group.itemIDs + [UUID()])
        try checkTrue(history.suppresses(smallChange))
        let subset = AutomaticGroup(id: "subset", title: "Related", reason: "Shared words", itemIDs: [a.id,excluded.id])
        try checkTrue(history.suppresses(subset))
        let mostlyNew = AutomaticGroup(id: "new", title: "Related", reason: "Shared words", itemIDs: group.itemIDs + (0..<4).map { _ in UUID() })
        try checkFalse(history.suppresses(mostlyNew))
        let unrelated = AutomaticGroup(id: "other", title: "Related", reason: "Shared words", itemIDs: [UUID(),UUID(),UUID()])
        try checkFalse(history.suppresses(unrelated))
        var duplicate = b; duplicate.contentHash = a.contentHash
        let duplicateGroup = try unwrap(Grouper.groups([a,duplicate]).first { $0.kind == .duplicates })
        try await reopened.dismissSuggestion(duplicateGroup)
        let duplicateHistory = try await reopened.groupReviewHistory()
        let newCopies = AutomaticGroup(id: "new-copies", title: "Duplicates", reason: "Identical", itemIDs: [UUID(),UUID()], kind: .duplicates, duplicateHash: a.contentHash)
        try checkTrue(duplicateHistory.suppresses(newCopies))
        let beforeReset = try await reopened.screenshots(); try checkEqual(beforeReset.count, 3)
        var settings = AutomationSettings(); settings.watchedPaths = [root.path]
        try await reopened.resetGroupReviews(settings: settings)
        let cleared = try await reopened.groupReviewHistory(); try checkTrue(cleared.decisions.isEmpty)
        let keptCollections = try await reopened.collections(); try checkEqual(keptCollections.count, 1)
        let keptItem = try await reopened.record(a.id); try checkEqual(keptItem?.collections, [collection.id])
        let keptSettings = try await reopened.settings(); try checkEqual(keptSettings?.watchedPaths, [root.path])
    }
    public func testGroupReviewValidationAndRollback() async throws {
        let root = try temporary(); let dbURL = root.appendingPathComponent("atomic.sqlite")
        let store = try LibraryStore(url: dbURL)
        let a = groupItem(root, number: 1), b = groupItem(root, number: 2)
        try await store.insert(a); try await store.insert(b)
        let group = AutomaticGroup(id: "atomic", title: "Review", reason: "Text", itemIDs: [a.id,b.id])
        for selection in [Set<UUID>(), Set([UUID()])] {
            var rejected = false
            do { try await store.acceptGroup(group, collection: Collection(name: "Invalid"), includedIDs: selection) } catch { rejected = true }
            try checkTrue(rejected)
        }
        for name in ["   ", String(repeating: "x", count: 121)] {
            var rejected = false
            do { try await store.acceptGroup(group, collection: Collection(name: name)) } catch { rejected = true }
            try checkTrue(rejected)
        }
        let missingID = UUID()
        let missingGroup = AutomaticGroup(id: "missing", title: "Review", reason: "Text", itemIDs: [a.id,missingID])
        var rejectedMissing = false
        do { try await store.acceptGroup(missingGroup, collection: Collection(name: "Missing record")) } catch { rejectedMissing = true }
        try checkTrue(rejectedMissing)
        let empty = try await store.collections(); try checkTrue(empty.isEmpty)
        // Inject a write failure to prove the collection, memberships, FTS and history roll back together.
        do {
            var db: OpaquePointer?
            try checkEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK)
            defer { sqlite3_close(db) }
            let sql = "CREATE TRIGGER reject_review BEFORE UPDATE ON screenshots WHEN OLD.id='\(b.id.uuidString)' BEGIN SELECT RAISE(ABORT, 'review failure fixture'); END;"
            try checkEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        }
        var failed = false
        do { try await store.acceptGroup(group, collection: Collection(name: "Rollback fixture")) }
        catch { failed = error.localizedDescription.contains("review failure fixture") }
        try checkTrue(failed)
        let collections = try await store.collections(); try checkTrue(collections.isEmpty)
        let records = try await store.screenshots(); try checkTrue(records.allSatisfy { $0.collections.isEmpty })
        let history = try await store.groupReviewHistory(); try checkTrue(history.decisions.isEmpty)
        let matches = try await store.searchIDs("Rollback fixture"); try checkTrue(matches.isEmpty)
    }
}
