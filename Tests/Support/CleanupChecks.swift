import Foundation
import GatherCore
import CSQLite

extension LibraryChecks {
    public func testCleanupMoveAndUndo() async throws {
        let root = try temporary(), destination = root.appendingPathComponent("Organized")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("Screenshot.png")
        try image(at: source)
        let bytes = try Data(contentsOf: source)
        let occupied = destination.appendingPathComponent("Screenshot.png")
        let foreign = Data("Existing destination".utf8); try foreign.write(to: occupied)
        let store = try LibraryStore(url: root.appendingPathComponent("db.sqlite"))
        _ = await Importer(store: store).run(urls: [source], sourceFolder: root.path) { _, _ in }
        var item = try unwrap(try await store.screenshots().first)
        item.title = "Personal reference"; item.favorite = true; item.tags = ["Custom"]; item.manualTags = true
        try await store.update(item)
        let service = CleanupService(store: store)
        let plan = try await service.plan(ids: [item.id], destination: destination)
        try checkTrue(plan.entries[0].destinationPath.hasSuffix("Screenshot (2).png"))
        let moved = try await service.execute(plan)
        try checkEqual(moved.entries[0].phase, .complete)
        try checkTrue(!FileManager.default.fileExists(atPath: source.path))
        try checkEqual(try Data(contentsOf: occupied), foreign)
        try checkEqual(try Data(contentsOf: URL(fileURLWithPath: moved.entries[0].destinationPath)), bytes)
        let updated = try unwrap(try await store.record(item.id))
        try checkEqual(updated.path, moved.entries[0].destinationPath)
        try checkEqual(updated.tags, item.tags); try checkEqual(updated.favorite, true); try checkEqual(updated.title, item.title)
        // Undo must preserve a newly occupied original path, and remain retryable.
        try foreign.write(to: source)
        let blocked = try await service.undo(plan.id)
        try checkEqual(blocked.entries[0].phase, .failed)
        try checkTrue(blocked.canUndo)
        try checkEqual(try Data(contentsOf: source), foreign)
        try FileManager.default.removeItem(at: source)
        let undone = try await service.undo(plan.id)
        try checkEqual(undone.entries[0].phase, .complete)
        try checkEqual(try Data(contentsOf: source), bytes)
        try checkEqual(try await store.record(item.id)?.path, source.path)
        try checkTrue(try await store.cleanupReservedPaths().isEmpty)
    }

    public func testCleanupPartialFailureAndRecovery() async throws {
        let root = try temporary(), destination = root.appendingPathComponent("Organized")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let a = root.appendingPathComponent("a.png"), b = root.appendingPathComponent("b.png")
        try image(at: a); try image(at: b)
        let store = try LibraryStore(url: root.appendingPathComponent("db.sqlite"))
        let importer = Importer(store: store)
        _ = await importer.run(urls: [a, b], sourceFolder: root.path) { _, _ in }
        let records = try await store.screenshots()
        let service = CleanupService(store: store)
        let plan = try await service.plan(ids: Set(records.map(\.id)), destination: destination)
        let collision = Data("Arrived after preview".utf8)
        try collision.write(to: URL(fileURLWithPath: plan.entries[0].destinationPath))
        let result = try await service.execute(plan)
        try checkEqual(result.entries.map(\.phase), [.failed, .complete])
        try checkEqual(try Data(contentsOf: URL(fileURLWithPath: plan.entries[0].destinationPath)), collision)
        try checkTrue(FileManager.default.fileExists(atPath: a.path))
        _ = try await service.undo(plan.id)
        // Simulate a crash after publishing and cataloguing, before original removal.
        let record = try unwrap(try await store.screenshots().first(where: { $0.path == b.path }))
        var interrupted = try await service.plan(ids: [record.id], destination: destination)
        try await store.beginCleanup(interrupted)
        let deferred = await importer.run(urls: [b], sourceFolder: root.path) { _, _ in }
        try checkTrue(deferred.deferredPaths.contains(b.path))
        var entry = interrupted.entries[0]
        entry.sourceIdentity = try CleanupService.identity(entry.from)
        try FileManager.default.copyItem(atPath: entry.from, toPath: entry.to)
        entry.copyIdentity = try CleanupService.identity(entry.to)
        entry.phase = .catalogued; interrupted.entries[0] = entry
        try await store.commitCleanupLocation(interrupted, index: 0, path: entry.to)
        let recovered = try await CleanupService(store: store).recover()
        try checkEqual(recovered.first(where: { $0.id == interrupted.id })?.entries[0].phase, .failed)
        try checkEqual(try await store.record(record.id)?.path, b.path)
        try checkTrue(!FileManager.default.fileExists(atPath: entry.to))
        try checkTrue(FileManager.default.fileExists(atPath: b.path))
        // Simulate a crash after verified source removal but before the final journal checkpoint.
        var finished = try await service.plan(ids: [record.id], destination: destination)
        try await store.beginCleanup(finished)
        entry = finished.entries[0]; entry.sourceIdentity = try CleanupService.identity(entry.from)
        try FileManager.default.copyItem(atPath: entry.from, toPath: entry.to)
        entry.copyIdentity = try CleanupService.identity(entry.to); entry.phase = .removingSource
        finished.entries[0] = entry
        try await store.commitCleanupLocation(finished, index: 0, path: entry.to)
        try FileManager.default.removeItem(atPath: entry.from)
        let restored = try await CleanupService(store: store).recover()
        try checkEqual(restored.first(where: { $0.id == finished.id })?.entries[0].phase, .complete)
        _ = try await service.undo(finished.id)
        try checkTrue(FileManager.default.fileExists(atPath: b.path))
        try checkTrue(try await store.cleanupReservedPaths().isEmpty)
    }
}

extension LibraryChecks {
    public func testCleanupDatabaseFailureAndOwnedRecovery() async throws {
        let root = try temporary(), destination = root.appendingPathComponent("Organized")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("Screenshot.png"); try image(at: source)
        let bytes = try Data(contentsOf: source), dbURL = root.appendingPathComponent("db.sqlite")
        let store = try LibraryStore(url: dbURL)
        _ = await Importer(store: store).run(urls: [source], sourceFolder: root.path) { _, _ in }
        let item = try unwrap(try await store.screenshots().first)
        let service = CleanupService(store: store)
        var plan = try await service.plan(ids: [item.id], destination: destination)
        var db: OpaquePointer?
        try checkEqual(sqlite3_open(dbURL.path, &db), SQLITE_OK); defer { sqlite3_close(db) }
        try checkEqual(sqlite3_exec(db, "CREATE TRIGGER reject_move BEFORE UPDATE ON screenshots BEGIN SELECT RAISE(ABORT, 'move failure fixture'); END;", nil, nil, nil), SQLITE_OK)
        var failed = false
        do { _ = try await service.execute(plan) } catch { failed = true }
        try checkTrue(failed)
        try checkEqual(try Data(contentsOf: source), bytes)
        try checkEqual(try await store.record(item.id)?.path, source.path)
        try checkEqual(sqlite3_exec(db, "DROP TRIGGER reject_move", nil, nil, nil), SQLITE_OK)
        _ = try await service.recover()
        try checkTrue(!FileManager.default.fileExists(atPath: plan.entries[0].to))
        // Recovery must not delete a replacement destination, even with identical bytes.
        plan = try await service.plan(ids: [item.id], destination: destination)
        try await store.beginCleanup(plan)
        var entry = plan.entries[0]
        entry.sourceIdentity = try CleanupService.identity(source.path)
        try FileManager.default.copyItem(atPath: entry.from, toPath: entry.stagingPath)
        entry.copyIdentity = try CleanupService.identity(entry.stagingPath)
        try FileManager.default.copyItem(atPath: entry.from, toPath: entry.to)
        entry.phase = .publishing; plan.entries[0] = entry
        try await store.checkpointCleanup(plan)
        _ = try await service.recover()
        try checkEqual(try Data(contentsOf: URL(fileURLWithPath: entry.to)), bytes)
        try checkTrue(!FileManager.default.fileExists(atPath: entry.stagingPath))
        try checkEqual(try Data(contentsOf: source), bytes)
        try checkTrue(try await store.cleanupReservedPaths().isEmpty)
    }
}
