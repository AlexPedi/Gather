import Foundation
import CSQLite
import GatherCore

extension LibraryChecks {
    public func seedGroupReviewLibrary(at url: URL) async throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = try LibraryStore(url: url)
        for number in 1...3 {
            let file = directory.appendingPathComponent("Screenshot group \(number).png")
            try createOCRFixture(at: file, extraLine: "Reservation reference \(number)")
            var item = try ImageService.inspect(file, sourceFolder: directory.path)
            item.title = "Hotel reservation \(number)"; item.manualTitle = true
            item.extractedText = "Hotel reservation confirmation flight departure airport booking"
            item.category = .travel; item.tags = ["Hotel", "Reservation"]
            item.ocrStatus = "complete"; item.taggingVersion = ContentTags.version
            try await store.insert(item)
        }
    }
    public func seedTagManagementLibrary(at url: URL) async throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("Screenshot fixture.png")
        try createOCRFixture(at: file)
        var item = try ImageService.inspect(file, sourceFolder: directory.path)
        item.tags = ["Children", "Research"]; item.manualTags = true
        item.ocrStatus = "complete"; item.taggingVersion = ContentTags.version
        let store = try LibraryStore(url: url)
        try await store.insert(item)
        try await store.saveTagCatalog(TagCatalog(names: ["Children", "Research", "Unused"]))
    }

    /// Read-only audit of real metadata. Report counts only, never screenshot text or tag names.
    public func auditTags(at url: URL) throws -> String {
        var db: OpaquePointer?
        try checkEqual(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        try checkEqual(sqlite3_prepare_v2(db, "SELECT payload FROM screenshots", -1, &stmt, nil), SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        var old: Set<String> = [], new: Set<String> = []
        var total = 0, eligible = 0, protected = 0, noise = 0
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let bytes = sqlite3_column_blob(stmt, 0) else { continue }
            let item = try JSONDecoder().decode(Screenshot.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0))))
            total += 1
            if item.manualTags { protected += 1; continue }
            guard item.ocrStatus == "complete" else { continue }
            eligible += 1
            old.formUnion(item.tags.map(ContentTags.key))
            noise += item.tags.filter { !ContentTags.isUseful($0) }.count
            new.formUnion(ContentTags.suggest(item.extractedText).map(ContentTags.key))
        }
        return "Read-only library audit: \(total) screenshots; \(eligible) eligible for refreshed suggestions; \(protected) manually tagged records protected. Unique automatic labels: \(old.count) before, \(new.count) after. Existing low-signal tag assignments excluded: \(noise). No library changes made."
    }
}
