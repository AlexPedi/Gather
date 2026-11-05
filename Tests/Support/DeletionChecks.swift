import Foundation
import GatherCore
import CSQLite

extension LibraryChecks {
    public func testScreenshotRemoval() async throws {
        let trashRoot = try temporary()
        let source = trashRoot.appendingPathComponent("delete.png")
        let trashed = trashRoot.appendingPathComponent("trash.png")
        try image(at: source)
        let trashStore = try LibraryStore(url: trashRoot.appendingPathComponent("trash.sqlite"))
        var item = try ImageService.inspect(source, sourceFolder: trashRoot.path)
        item.extractedText = "trashfixture"
        try await trashStore.insert(item)
        // Recycling failures retain the library entry and original.
        var failed = false
        do { try await trashStore.trashScreenshot(item.id) { _ in throw LibraryError.database("Denied") } }
        catch { failed = true }
        try checkTrue(failed)
        try checkTrue(FileManager.default.fileExists(atPath: source.path))
        try checkEqual(try await trashStore.record(item.id), item)
        // A database failure restores the recycled file before surfacing the error.
        var db: OpaquePointer?
        try checkEqual(sqlite3_open(trashRoot.appendingPathComponent("trash.sqlite").path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        try checkEqual(sqlite3_exec(db, "CREATE TRIGGER reject_delete BEFORE DELETE ON screenshots BEGIN SELECT RAISE(ABORT, 'fixture'); END;", nil, nil, nil), SQLITE_OK)
        failed = false
        do {
            try await trashStore.trashScreenshot(item.id) { url in
                try FileManager.default.moveItem(at: url, to: trashed); return trashed
            }
        } catch { failed = true }
        try checkTrue(failed)
        try checkTrue(FileManager.default.fileExists(atPath: source.path))
        try checkEqual(try await trashStore.record(item.id), item)
        try checkEqual(sqlite3_exec(db, "DROP TRIGGER reject_delete", nil, nil, nil), SQLITE_OK)
        try await trashStore.trashScreenshot(item.id) { url in
            try FileManager.default.moveItem(at: url, to: trashed); return trashed
        }
        try checkTrue(!FileManager.default.fileExists(atPath: source.path))
        try checkTrue(FileManager.default.fileExists(atPath: trashed.path))
        try checkEqual(try await trashStore.record(item.id), nil)
        try checkTrue(try await trashStore.searchIDs("trashfixture").isEmpty)
        let root = try temporary(), dbURL = root.appendingPathComponent("removal.sqlite")
        let store = try LibraryStore(url: dbURL)
        let path = root.appendingPathComponent("original.png")
        try Data("untouched original".utf8).write(to: path)
        var a = Screenshot(path: path.path, sourceFolder: root.path, captureDate: Date(), fileSize: 18, width: 10, height: 10, contentHash: "original")
        a.extractedText = "deletionfixture"; a.ocrStatus = "complete"
        var b = a; b.id = UUID(); b.path = root.appendingPathComponent("other.png").path
        try await store.insert(a); try await store.insert(b)
        // Invalid selections must roll back all removals and suppression history.
        var rejected = false
        do { try await store.removeScreenshots(ids: [a.id, UUID()]) } catch { rejected = true }
        try checkTrue(rejected)
        try checkEqual(try await store.screenshots().count, 2)
        try await store.removeScreenshots(ids: [a.id])
        try checkEqual(try await store.record(a.id), nil)
        try checkEqual(try await store.searchIDs("deletionfixture"), [b.id])
        try checkEqual(try Data(contentsOf: path), Data("untouched original".utf8))
        // Late OCR or stale updates cannot resurrect deleted search entries.
        try await store.completeOCR(a.id, hash: a.contentHash, text: "resurrected")
        try await store.update(a)
        try checkTrue(try await store.searchIDs("resurrected").isEmpty)
        try checkEqual(try await store.searchIDs("deletionfixture"), [b.id])
        let reopened = try LibraryStore(url: dbURL)
        try checkEqual(try await reopened.insert(a, automatic: true), false)
        try checkEqual(try await reopened.insert(a), true)
        try await reopened.removeScreenshots(ids: [a.id])
        a.id = UUID(); a.contentHash = "new bytes"
        try checkEqual(try await reopened.insert(a, automatic: true), true)
    }
}
