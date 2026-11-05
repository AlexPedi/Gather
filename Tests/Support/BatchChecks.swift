import Foundation
import CSQLite
import GatherCore

extension LibraryChecks {
    public func testBatchActionsAndRollback() async throws {
        let root = try temporary(), dbURL = root.appendingPathComponent("batch.sqlite")
        let store = try LibraryStore(url: dbURL)
        var a = Screenshot(path: root.appendingPathComponent("a.png").path, sourceFolder: root.path, captureDate: Date(), fileSize: 10, width: 10, height: 10, contentHash: "a")
        a.extractedText = "Recognized mortgage information"; a.title = "Manual title"; a.manualTitle = true; a.ocrStatus = "complete"; a.tags = ["Keep"]
        var b = a; b.id = UUID(); b.path = root.appendingPathComponent("b.png").path; b.contentHash = "b"; b.tags = ["Other"]
        var excluded = b; excluded.id = UUID(); excluded.path = root.appendingPathComponent("excluded.png").path
        for item in [a,b,excluded] { try await store.insert(item) }
        let ids: Set<UUID> = [a.id,b.id]
        try await store.renameTag("Old", to: "Canonical")
        try await store.applyBatch(ids: ids, action: .addTag("Old"))
        try await store.applyBatch(ids: ids, action: .favorite(true))
        let collection = Collection(name: "Batch collection"); try await store.save(collection)
        try await store.applyBatch(ids: ids, action: .addToCollection(collection.id))
        try await store.applyBatch(ids: ids, action: .addToCollection(collection.id))
        let updated = try unwrap(try await store.record(a.id))
        try checkEqual(updated.tags, ["Keep", "Canonical"])
        try checkEqual(updated.collections, [collection.id]); try checkTrue(updated.favorite)
        try checkTrue(updated.manualTags); try checkEqual(updated.extractedText, a.extractedText)
        try checkEqual(updated.path, a.path); try checkEqual(updated.title, a.title); try checkEqual(updated.contentHash, a.contentHash)
        try checkEqual(try await store.record(excluded.id), excluded)
        try checkEqual(try await store.searchIDs("Canonical"), ids)
        try checkEqual(try await store.searchIDs("Batch collection"), ids)
        try await store.applyBatch(ids: ids, action: .removeTag("Old"))
        try checkEqual(try await store.record(a.id)?.tags, ["Keep"])
        try checkEqual(try await store.record(b.id)?.tags, ["Other"])
        try await store.applyBatch(ids: ids, action: .favorite(false))
        try checkEqual(try await store.record(b.id)?.favorite, false)
        // Every validation error rejects the whole operation.
        for action: BatchAction in [.addTag("bad,tag"), .addTag("\n"), .addToCollection(UUID())] {
            var rejected = false
            do { try await store.applyBatch(ids: ids, action: action) } catch { rejected = true }
            try checkTrue(rejected)
        }
        var missingRejected = false
        do { try await store.applyBatch(ids: [a.id,UUID()], action: .favorite(true)) } catch { missingRejected = true }
        try checkTrue(missingRejected); try checkEqual(try await store.record(a.id)?.favorite, false)
        // Fail one write after the catalog update: all records, catalog and FTS must roll back.
        var db: OpaquePointer?
        try checkEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK); defer { sqlite3_close(db) }
        try checkEqual(sqlite3_exec(db, "CREATE TRIGGER reject_batch BEFORE UPDATE ON screenshots WHEN OLD.id='\(b.id.uuidString)' BEGIN SELECT RAISE(ABORT, 'batch failure fixture'); END;", nil, nil, nil), SQLITE_OK)
        var failed = false
        do { try await store.applyBatch(ids: ids, action: .addTag("RollbackTag")) } catch { failed = true }
        try checkTrue(failed)
        try checkTrue(try await store.searchIDs("RollbackTag").isEmpty)
        try checkTrue(try await store.tagCatalog().names.allSatisfy { $0 != "RollbackTag" })
        try checkEqual(try await store.record(a.id)?.tags, ["Keep"])
        let reopened = try LibraryStore(url: dbURL)
        try checkEqual(try await reopened.record(a.id)?.collections, [collection.id])
    }
}
