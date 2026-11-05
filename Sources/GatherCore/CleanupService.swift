import Foundation
import Darwin

/// Serial file operations, durable checkpoints, and exact identities for app-owned temporary files.
public actor CleanupService {
    private let store: LibraryStore
    private var running = false
    public init(store: LibraryStore) { self.store = store }
    public static func pathKey(_ path: String) -> String { URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path.lowercased() }
    public static func identity(_ path: String) throws -> FileIdentity {
        var info = stat()
        guard lstat(path, &info) == 0 else { throw CocoaError(.fileReadNoSuchFile) }
        guard info.st_mode & S_IFMT == S_IFREG else { throw CleanupError.problem("Only regular image files can be moved; symbolic links are not moved.") }
        return FileIdentity(device: UInt64(UInt32(bitPattern: info.st_dev)), inode: UInt64(info.st_ino))
    }
    private static func exists(_ path: String) -> Bool { var info = stat(); return lstat(path, &info) == 0 }
    private static func verified(_ path: String, hash: String, identity: FileIdentity? = nil) -> Bool {
        guard let actual = try? Self.identity(path), identity == nil || actual == identity else { return false }
        return (try? ImageService.hash(URL(fileURLWithPath: path))) == hash
    }
    private static func exclusiveRename(_ from: String, _ to: String) throws {
        guard renamex_np(from, to, UInt32(RENAME_EXCL)) == 0 else {
            let code = errno
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSLocalizedDescriptionKey: "Cannot move to \(to): \(String(cString: strerror(code))). No existing file was overwritten."])
        }
    }
    public func plan(ids: Set<UUID>, destination: URL) async throws -> CleanupOperation {
        guard !running else { throw CleanupError.problem("Wait for the current file operation to finish.") }
        let destination = destination.standardizedFileURL.resolvingSymlinksInPath()
        guard try destination.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw CleanupError.problem("Choose an existing destination folder.") }
        let all = try await store.screenshots()
        let selected = all.filter { ids.contains($0.id) }.sorted { $0.path < $1.path }
        guard selected.count == ids.count, !ids.isEmpty else { throw CleanupError.problem("Select screenshots that are still in the library.") }
        var occupied = Set(all.map { Self.pathKey($0.path) })
        occupied.formUnion(try await store.cleanupReservedPaths())
        var entries: [CleanupEntry] = []
        for item in selected {
            var entry = CleanupEntry(screenshotID: item.id, title: item.title, originalPath: item.path,
                                     destinationPath: destination.appendingPathComponent(URL(fileURLWithPath: item.path).lastPathComponent).path, expectedHash: item.contentHash)
            if Self.pathKey(URL(fileURLWithPath: item.path).deletingLastPathComponent().path) == Self.pathKey(destination.path) {
                entry.phase = .skipped; entry.detail = "Already in the destination folder."
            } else if try await store.isCleanupReserved(item.path) {
                entry.phase = .skipped; entry.detail = "An unfinished operation needs to be checked first."
            } else {
                do { _ = try Self.identity(item.path) } catch { entry.phase = .skipped; entry.detail = error.localizedDescription }
                let file = URL(fileURLWithPath: item.path)
                var counter = 1
                while Self.exists(entry.destinationPath) || occupied.contains(Self.pathKey(entry.destinationPath)) {
                    counter += 1
                    guard counter < 10_000 else { throw CleanupError.problem("Could not find an available destination filename.") }
                    var base = file.deletingPathExtension().lastPathComponent
                    let suffix = " (\(counter)).\(file.pathExtension)"
                    while (base + suffix).utf8.count > 240 { base.removeLast() }
                    entry.destinationPath = destination.appendingPathComponent(base + suffix).path
                }
                occupied.insert(Self.pathKey(entry.destinationPath))
            }
            entries.append(entry)
        }
        return CleanupOperation(destinationFolder: destination.path, entries: entries)
    }
    public func execute(_ preview: CleanupOperation, progress: @Sendable (Int, Int) async -> Void = { _, _ in }) async throws -> CleanupOperation {
        guard !running else { throw CleanupError.problem("A file operation is already running.") }
        running = true; defer { running = false }
        try await store.beginCleanup(preview)
        return try await run(preview, progress: progress)
    }
    public func undo(_ id: UUID, progress: @Sendable (Int, Int) async -> Void = { _, _ in }) async throws -> CleanupOperation {
        guard !running else { throw CleanupError.problem("A file operation is already running.") }
        running = true; defer { running = false }
        guard var operation = try await store.cleanupOperation(id), operation.canUndo else { throw CleanupError.problem("No completed moves can be undone in this operation.") }
        for index in operation.entries.indices where operation.entries[index].canUndo {
            operation.entries[index].direction = .undo; operation.entries[index].phase = .pending
            operation.entries[index].detail = nil; operation.entries[index].sourceIdentity = nil; operation.entries[index].copyIdentity = nil
        }
        try await store.beginCleanup(operation, undo: true)
        return try await run(operation, progress: progress)
    }
    private func run(_ input: CleanupOperation, progress: @Sendable (Int, Int) async -> Void) async throws -> CleanupOperation {
        var operation = input
        for index in operation.entries.indices where operation.entries[index].phase == .pending {
            do { try await transfer(&operation, index: index) }
            catch {
                operation.entries[index].detail = error.localizedDescription
                operation = try await reconcile(operation, index: index, failure: error.localizedDescription)
            }
            await progress(index + 1, operation.entries.count)
        }
        return operation
    }
    private func transfer(_ operation: inout CleanupOperation, index: Int) async throws {
        var entry = operation.entries[index]
        guard !Self.exists(entry.to), !Self.exists(entry.stagingPath), !Self.exists(entry.holdingPath) else {
            throw CleanupError.problem("A destination or temporary filename is now occupied. Nothing will be overwritten; preview again.")
        }
        guard let latest = try await store.record(entry.screenshotID), latest.path == entry.from, latest.contentHash == entry.expectedHash,
              Self.verified(entry.from, hash: entry.expectedHash) else { throw CleanupError.problem("The original changed or became unavailable since preview. No source file was removed.") }
        entry.sourceIdentity = try Self.identity(entry.from)
        entry.phase = .copying; operation.entries[index] = entry; try await store.checkpointCleanup(operation)
        let descriptor = open(entry.stagingPath, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CleanupError.problem("Cannot create a private destination copy: \(String(cString: strerror(errno)))") }
        let output = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? output.close() }
        entry.copyIdentity = try Self.identity(entry.stagingPath)
        operation.entries[index] = entry; try await store.checkpointCleanup(operation)
        let source = try FileHandle(forReadingFrom: URL(fileURLWithPath: entry.from)); defer { try? source.close() }
        while let data = try source.read(upToCount: 1024 * 1024), !data.isEmpty { try output.write(contentsOf: data) }
        guard fcopyfile(source.fileDescriptor, output.fileDescriptor, nil, copyfile_flags_t(COPYFILE_METADATA)) == 0 else {
            throw CleanupError.problem("Could not preserve the file's metadata. Its original was retained.")
        }
        try output.synchronize(); try output.close()
        guard Self.verified(entry.stagingPath, hash: entry.expectedHash, identity: entry.copyIdentity),
              Self.verified(entry.from, hash: entry.expectedHash, identity: entry.sourceIdentity) else { throw CleanupError.problem("The original changed during copying. Its source was not removed.") }
        let attributes = try FileManager.default.attributesOfItem(atPath: entry.from)
        var dates: [FileAttributeKey: Any] = [:]
        for key in [FileAttributeKey.creationDate, .modificationDate, .posixPermissions] { dates[key] = attributes[key] }
        try FileManager.default.setAttributes(dates, ofItemAtPath: entry.stagingPath)
        entry.phase = .publishing; operation.entries[index] = entry; try await store.checkpointCleanup(operation)
        try Self.exclusiveRename(entry.stagingPath, entry.to)
        guard Self.verified(entry.to, hash: entry.expectedHash, identity: entry.copyIdentity) else { throw CleanupError.problem("Destination verification failed. The original is retained.") }
        entry.phase = .published; operation.entries[index] = entry; try await store.checkpointCleanup(operation)
        entry.phase = .catalogued; operation.entries[index] = entry
        try await store.commitCleanupLocation(operation, index: index, path: entry.to)
        guard Self.verified(entry.from, hash: entry.expectedHash, identity: entry.sourceIdentity) else { throw CleanupError.problem("The source changed before removal; both locations were retained for review.") }
        entry.phase = .removingSource; operation.entries[index] = entry; try await store.checkpointCleanup(operation)
        try Self.exclusiveRename(entry.from, entry.holdingPath)
        guard Self.verified(entry.holdingPath, hash: entry.expectedHash, identity: entry.sourceIdentity) else { throw CleanupError.problem("The source changed. Its held original was not deleted.") }
        try FileManager.default.removeItem(atPath: entry.holdingPath)
        entry.phase = .complete; entry.detail = nil; operation.entries[index] = entry
        try await store.checkpointCleanup(operation, releasing: index)
    }
    /// Recovery never removes a user source. It restores held originals or reconciles a verified completed move.
    private func reconcile(_ input: CleanupOperation, index: Int, failure: String) async throws -> CleanupOperation {
        var operation = input
        var entry = operation.entries[index]
        if entry.phase == .pending || entry.phase == .copying {
            if let copy = entry.copyIdentity, (try? Self.identity(entry.stagingPath)) == copy { try? FileManager.default.removeItem(atPath: entry.stagingPath) }
            entry.phase = Self.exists(entry.stagingPath) ? .needsAttention : .failed
            entry.detail = failure + " No source was removed."
            operation.entries[index] = entry
            try await store.checkpointCleanup(operation, releasing: entry.phase == .failed ? index : nil)
            return operation
        }
        if !Self.exists(entry.from), (try? Self.identity(entry.holdingPath)) != nil {
            // Restore even an externally modified held source; never delete unverified source bytes.
            try? Self.exclusiveRename(entry.holdingPath, entry.from)
        }
        let sourceOK = Self.verified(entry.from, hash: entry.expectedHash, identity: entry.sourceIdentity)
        let destinationOwned = entry.copyIdentity != nil && Self.verified(entry.to, hash: entry.expectedHash, identity: entry.copyIdentity)
        if sourceOK {
            entry.phase = .needsAttention; entry.detail = failure; operation.entries[index] = entry
            try await store.commitCleanupLocation(operation, index: index, path: entry.from)
            // Only remove an app-created copy with the journaled identity; never remove a colliding destination.
            if destinationOwned { try? FileManager.default.removeItem(atPath: entry.to) }
            if let copy = entry.copyIdentity, (try? Self.identity(entry.stagingPath)) == copy { try? FileManager.default.removeItem(atPath: entry.stagingPath) }
            let artifactsRemain = Self.exists(entry.stagingPath) || Self.exists(entry.holdingPath) || (destinationOwned && Self.exists(entry.to))
            entry.phase = artifactsRemain ? .needsAttention : .failed
            entry.detail = failure + (artifactsRemain ? " Check the operation paths in Finder; originals were retained." : " Original retained; no existing destination was overwritten.")
        } else if destinationOwned && !Self.exists(entry.from) && !Self.exists(entry.holdingPath) {
            entry.phase = .complete; entry.detail = "Verified destination recovered after interruption."
            operation.entries[index] = entry; try await store.commitCleanupLocation(operation, index: index, path: entry.to)
        } else {
            entry.phase = .needsAttention
            entry.detail = failure + " Files were not removed during recovery. Restore access or resolve the listed paths, then Check Again."
            if destinationOwned { operation.entries[index] = entry; try await store.commitCleanupLocation(operation, index: index, path: entry.to) }
        }
        operation.entries[index] = entry
        try await store.checkpointCleanup(operation, releasing: entry.phase == .complete || entry.phase == .failed ? index : nil)
        return operation
    }
    public func recover() async throws -> [CleanupOperation] {
        guard !running else { throw CleanupError.problem("Wait for the current file operation.") }
        running = true; defer { running = false }
        for var operation in try await store.cleanupOperations() {
            for index in operation.entries.indices where operation.entries[index].phase.isActive || operation.entries[index].phase == .needsAttention {
                operation = try await reconcile(operation, index: index, failure: operation.entries[index].detail ?? "Interrupted operation.")
            }
        }
        return try await store.cleanupOperations()
    }
}
