import Foundation
import CSQLite

/// All SQLite access is confined to this actor. JSON holds the complete model;
/// indexed columns enforce identity and allow future migrations without losing metadata.
public actor LibraryStore {
    private let connection: SQLiteConnection
    private var db: OpaquePointer? { connection.handle }
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var connection: OpaquePointer?
        guard sqlite3_open(url.path, &connection) == SQLITE_OK else {
            if let connection { sqlite3_close(connection) }
            throw LibraryError.database("Unable to open database")
        }
        self.connection = SQLiteConnection(connection)
        do {
            try Self.execute(connection, "PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000;")
            let version = sqlite3_prepare_v2(connection, "PRAGMA user_version", -1, &migrationStatement, nil)
            guard version == SQLITE_OK else { throw LibraryError.database("Cannot read schema version") }
            sqlite3_step(migrationStatement)
            let schema = sqlite3_column_int(migrationStatement, 0)
            sqlite3_finalize(migrationStatement); migrationStatement = nil
            guard schema <= 4 else { throw LibraryError.database("This library requires a newer Gather version") }
            if schema == 0 {
                try Self.execute(connection, """
                BEGIN IMMEDIATE;
                CREATE TABLE screenshots (id TEXT PRIMARY KEY, path TEXT NOT NULL UNIQUE, hash TEXT NOT NULL, payload BLOB NOT NULL);
                CREATE INDEX screenshot_hash ON screenshots(hash);
                CREATE TABLE collections (id TEXT PRIMARY KEY, payload BLOB NOT NULL);
                CREATE TABLE access (path TEXT PRIMARY KEY, payload BLOB NOT NULL);
                PRAGMA user_version=1;
                COMMIT;
                """)
            }
            if schema < 2 {
                try Self.execute(connection, """
                BEGIN IMMEDIATE;
                ALTER TABLE screenshots ADD COLUMN ocr_status TEXT NOT NULL DEFAULT 'pending';
                CREATE INDEX screenshot_processing ON screenshots(ocr_status);
                CREATE TABLE preferences (key TEXT PRIMARY KEY, payload BLOB NOT NULL);
                CREATE VIRTUAL TABLE search USING fts5(id UNINDEXED, document, tokenize='unicode61');
                INSERT INTO search(id,document) SELECT id,CAST(payload AS TEXT) FROM screenshots;
                PRAGMA user_version=2;
                COMMIT;
                """)
            }
            if schema < 3 {
                try Self.execute(connection, """
                BEGIN IMMEDIATE;
                ALTER TABLE screenshots ADD COLUMN tag_version INTEGER NOT NULL DEFAULT 0;
                PRAGMA user_version=3;
                COMMIT;
                """)
            }
            if schema < 4 {
                try Self.execute(connection, """
                BEGIN IMMEDIATE;
                CREATE TABLE cleanup_operations (id TEXT PRIMARY KEY, created REAL NOT NULL, payload BLOB NOT NULL);
                CREATE TABLE cleanup_paths (path TEXT PRIMARY KEY, screenshot_id TEXT NOT NULL, operation_id TEXT NOT NULL);
                CREATE INDEX cleanup_screenshot ON cleanup_paths(screenshot_id);
                PRAGMA user_version=4;
                COMMIT;
                """)
            }
        } catch { throw error }
    }
    private var migrationStatement: OpaquePointer?


    private static func execute(_ db: OpaquePointer?, _ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw LibraryError.database(String(cString: sqlite3_errmsg(db)))
        }
    }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw LibraryError.database(String(cString: sqlite3_errmsg(db)))
        }
        return stmt
    }
    private func bind(_ value: String, to index: Int32, in stmt: OpaquePointer) {
        _ = value.withCString { sqlite3_bind_text(stmt, index, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
    }
    private func bind<T: Encodable>(_ value: T, to index: Int32, in stmt: OpaquePointer) throws {
        let data = try encoder.encode(value)
        _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, index, $0.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
    }
    private func finish(_ stmt: OpaquePointer) throws {
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw LibraryError.database(String(cString: sqlite3_errmsg(db))) }
    }
    private func payloads<T: Decodable>(_ type: T.Type, sql: String) throws -> [T] {
        let stmt = try statement(sql); defer { sqlite3_finalize(stmt) }
        var values: [T] = []
        while true {
            let result = sqlite3_step(stmt)
            if result == SQLITE_DONE { return values }
            guard result == SQLITE_ROW, let bytes = sqlite3_column_blob(stmt, 0) else {
                throw LibraryError.database(String(cString: sqlite3_errmsg(db)))
            }
            values.append(try decoder.decode(type, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0)))))
        }
    }
    public func screenshots() throws -> [Screenshot] { try payloads(Screenshot.self, sql: "SELECT payload FROM screenshots") }
    public func collections() throws -> [Collection] { try payloads(Collection.self, sql: "SELECT payload FROM collections") }
    public func permissions() throws -> [SavedAccess] { try payloads(SavedAccess.self, sql: "SELECT payload FROM access") }
    private func transaction<T>(_ work: () throws -> T) throws -> T {
        try Self.execute(db, "BEGIN IMMEDIATE")
        do { let value = try work(); try Self.execute(db, "COMMIT"); return value }
        catch { try? Self.execute(db, "ROLLBACK"); throw error }
    }
    private func index(_ item: Screenshot) throws {
        let remove = try statement("DELETE FROM search WHERE id=?")
        bind(item.id.uuidString, to: 1, in: remove)
        defer { sqlite3_finalize(remove) }
        try finish(remove)
        let insert = try statement("INSERT INTO search(id,document) VALUES(?,?)")
        defer { sqlite3_finalize(insert) }
        let names = try collections().filter { item.collections.contains($0.id) }.map(\.name)
        let document = ([item.title, item.originalFilename, item.extractedText, item.category.rawValue] + item.tags + names).joined(separator: " ")
        bind(item.id.uuidString, to: 1, in: insert); bind(document, to: 2, in: insert); try finish(insert)
    }
    public func record(_ id: UUID) throws -> Screenshot? {
        let stmt = try statement("SELECT payload FROM screenshots WHERE id=?")
        defer { sqlite3_finalize(stmt) }; bind(id.uuidString, to: 1, in: stmt)
        let result = sqlite3_step(stmt)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW, let bytes = sqlite3_column_blob(stmt, 0) else { throw LibraryError.database("Cannot read record") }
        return try decoder.decode(Screenshot.self, from: Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0))))
    }
    private func removedSources() throws -> [String: String] {
        try payloads([String: String].self, sql: "SELECT payload FROM preferences WHERE key='removedSources'").first ?? [:]
    }
    private func saveRemovedSources(_ sources: [String: String]) throws {
        let stmt = try statement("INSERT INTO preferences(key,payload) VALUES('removedSources',?) ON CONFLICT(key) DO UPDATE SET payload=excluded.payload")
        defer { sqlite3_finalize(stmt) }
        try bind(sources, to: 1, in: stmt); try finish(stmt)
    }
    /// Remove metadata and search entries together. Automatic intake skips the same
    /// source bytes afterward; explicit import can add them again.
    public func removeScreenshots(ids: Set<UUID>) throws {
        try transaction {
            var removed = try removedSources()
            for id in ids {
                guard let item = try record(id) else { throw LibraryError.database("A selected screenshot no longer exists.") }
                guard try !isCleanupReserved(item.path) else { throw LibraryError.database("Wait for the file operation to finish before deleting this screenshot.") }
                removed[item.path] = item.contentHash
                for sql in ["DELETE FROM search WHERE id=?", "DELETE FROM screenshots WHERE id=?"] {
                    let stmt = try statement(sql)
                    defer { sqlite3_finalize(stmt) }
                    bind(id.uuidString, to: 1, in: stmt); try finish(stmt)
                }
            }
            try saveRemovedSources(removed)
        }
    }
    /// Keep the actor isolated across validation, recycling and metadata removal.
    /// The injectable recycler lets checks use an isolated temporary Trash folder.
    public func trashScreenshot(_ id: UUID, recycle: @Sendable (URL) throws -> URL = { source in
        var destination: NSURL?
        try FileManager.default.trashItem(at: source, resultingItemURL: &destination)
        guard let destination else { throw LibraryError.database("The file moved to Trash, but macOS did not return its location.") }
        return destination as URL
    }) throws {
        guard let item = try record(id) else { throw LibraryError.database("The screenshot no longer exists.") }
        guard try !isCleanupReserved(item.path) else { throw LibraryError.database("Wait for the file operation to finish before deleting this screenshot.") }
        let source = URL(fileURLWithPath: item.path)
        let current = try ImageService.inspect(source, sourceFolder: item.sourceFolder)
        guard current.contentHash == item.contentHash else {
            throw LibraryError.database("The original file has changed. Reimport it before deleting.")
        }
        let trashed = try recycle(source)
        do { try removeScreenshots(ids: [id]) }
        catch {
            // Restore the original if the database could not commit the removal.
            do {
                guard !FileManager.default.fileExists(atPath: source.path) else {
                    throw LibraryError.database("The original path is now occupied.")
                }
                try FileManager.default.moveItem(at: trashed, to: source)
            } catch {
                throw LibraryError.database("The file is in Trash, but its library entry could not be removed. Restore it from Trash and retry. \(error.localizedDescription)")
            }
            throw error
        }
    }
    @discardableResult public func insert(_ item: Screenshot, automatic: Bool = false) throws -> Bool {
        try transaction {
            if try isCleanupReserved(item.path) { return false }
            var removed = try removedSources()
            if automatic, removed[item.path] == item.contentHash { return false }
            removed.removeValue(forKey: item.path)
            try saveRemovedSources(removed)
            let stmt = try statement("INSERT OR IGNORE INTO screenshots(id,path,hash,payload,ocr_status,tag_version) VALUES(?,?,?,?,?,?)")
            defer { sqlite3_finalize(stmt) }
            bind(item.id.uuidString, to: 1, in: stmt); bind(item.path, to: 2, in: stmt)
            bind(item.contentHash, to: 3, in: stmt); try bind(item, to: 4, in: stmt); bind(item.ocrStatus, to: 5, in: stmt)
            sqlite3_bind_int(stmt, 6, Int32(item.taggingVersion ?? 0))
            try finish(stmt)
            let added = sqlite3_changes(db) == 1
            if added { try index(item) }
            return added
        }
    }
    public func update(_ item: Screenshot) throws {
        if let current = try record(item.id), current.path != item.path, try isCleanupReserved(current.path) {
            throw CleanupError.problem("A file operation is updating this screenshot. Wait before relocating it.")
        }
        try transaction { try write(item) }
    }
    private func write(_ item: Screenshot) throws {
        guard try record(item.id) != nil else { return }
        let stmt = try statement("UPDATE screenshots SET path=?,hash=?,payload=?,ocr_status=?,tag_version=? WHERE id=?")
        defer { sqlite3_finalize(stmt) }
        bind(item.path, to: 1, in: stmt); bind(item.contentHash, to: 2, in: stmt)
        try bind(item, to: 3, in: stmt); bind(item.ocrStatus, to: 4, in: stmt); sqlite3_bind_int(stmt, 5, Int32(item.taggingVersion ?? 0)); bind(item.id.uuidString, to: 6, in: stmt)
        try finish(stmt); try index(item)
    }
    /// Merge only user-owned metadata; never overwrite concurrent OCR results with a stale view snapshot.
    public func updateMetadata(_ edit: Screenshot) throws {
        guard var latest = try record(edit.id) else { return }
        if edit.manualTitle { latest.title = edit.title; latest.manualTitle = true }
        if edit.manualCategory { latest.category = edit.category; latest.manualCategory = true }
        if edit.manualTags { latest.tags = try tagRules().apply(edit.tags, automatic: false); latest.manualTags = true }
        latest.favorite = edit.favorite; latest.inbox = edit.inbox; latest.collections = edit.collections
        try update(latest)
    }
    /// Apply one field-level action to the latest records, atomically with their search documents.
    public func applyBatch(ids: Set<UUID>, action: BatchAction) throws {
        guard !ids.isEmpty else { throw LibraryError.database("Select at least one screenshot") }
        try transaction {
            let rules = try tagRules()
            var tag: String?
            switch action {
            case .addTag(let raw), .removeTag(let raw):
                let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, name.count <= 60, !name.contains(","), !name.contains(where: { $0.isNewline }) else {
                    throw LibraryError.database("Enter a tag name of 1–60 characters without commas or newlines")
                }
                tag = rules.resolved(name)
            case .addToCollection(let id):
                guard try collections().contains(where: { $0.id == id }) else { throw LibraryError.database("The collection no longer exists") }
            case .favorite: break
            }
            // Validate the entire selection before writing, including deleted/stale IDs.
            var records: [Screenshot] = []
            for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) {
                guard let item = try record(id) else { throw LibraryError.database("A selected screenshot no longer exists. Select again.") }
                records.append(item)
            }
            if case .addTag = action, let tag {
                var catalog = try tagCatalog(); catalog.names.append(tag); try saveTagCatalog(catalog)
            }
            for var item in records {
                switch action {
                case .favorite(let value): item.favorite = value
                case .addTag:
                    item.tags = rules.apply(item.tags + [tag!], automatic: false); item.manualTags = true
                case .removeTag:
                    item.tags = rules.apply(item.tags, automatic: false).filter { ContentTags.key($0) != ContentTags.key(tag!) }; item.manualTags = true
                case .addToCollection(let id): if !item.collections.contains(id) { item.collections.append(id) }
                }
                try write(item)
            }
        }
    }
    public func refreshSource(_ id: UUID, source: Screenshot) throws {
        guard var latest = try record(id), try !isCleanupReserved(latest.path) else { return }
        latest.contentHash = source.contentHash; latest.thumbnailKey = source.thumbnailKey
        latest.fileSize = source.fileSize; latest.width = source.width; latest.height = source.height
        latest.captureDate = source.captureDate; latest.extractedText = ""; latest.ocrStatus = "pending"
        latest.processingError = nil; latest.retryCount = 0; latest.taggingVersion = nil
        if !latest.manualTitle { latest.title = source.title }
        if !latest.manualCategory { latest.category = .uncategorized }
        if !latest.manualTags { latest.tags = [] }
        try update(latest)
    }
    public func completeOCR(_ id: UUID, hash: String, text: String) throws {
        guard var item = try record(id), item.contentHash == hash else { return }
        let suggestion = Classifier.suggest(text: text)
        item.extractedText = text; item.taggingVersion = ContentTags.version; item.ocrStatus = "complete"; item.processingError = nil
        if !item.manualTitle, let title = suggestion.title { item.title = title }
        if !item.manualCategory { item.category = suggestion.category }
        if !item.manualTags { item.tags = try tagRules().apply(suggestion.tags, automatic: true) }
        try update(item)
    }
    public func setProcessing(_ id: UUID, status: String, error: String? = nil, hash: String? = nil) throws {
        guard var item = try record(id) else { return }
        if let hash, item.contentHash != hash { return }
        item.ocrStatus = status; item.processingError = error
        if status == "failed" { item.retryCount += 1 }
        try update(item)
    }
    public func nextTagsPending() throws -> Screenshot? {
        try payloads(Screenshot.self, sql: "SELECT payload FROM screenshots WHERE ocr_status='complete' AND tag_version<\(ContentTags.version) ORDER BY rowid LIMIT 1").first
    }
    public func completeTags(_ id: UUID, hash: String, tags: [String]) throws {
        guard var item = try record(id), item.contentHash == hash else { return }
        if !item.manualTags { item.tags = try tagRules().apply(tags, automatic: true) }
        item.taggingVersion = ContentTags.version; try update(item)
    }
    public func tagCatalog() throws -> TagCatalog {
        try payloads(TagCatalog.self, sql: "SELECT payload FROM preferences WHERE key='tags'").first ?? TagCatalog()
    }
    public func saveTagCatalog(_ catalog: TagCatalog) throws {
        let stmt = try statement("INSERT INTO preferences(key,payload) VALUES('tags',?) ON CONFLICT(key) DO UPDATE SET payload=excluded.payload")
        defer { sqlite3_finalize(stmt) }
        let normalized = TagCatalog(names: try tagRules().apply(catalog.names, automatic: false))
        try bind(normalized, to: 1, in: stmt); try finish(stmt)
    }
    public func tagRules() throws -> TagRules {
        try payloads(TagRules.self, sql: "SELECT payload FROM preferences WHERE key='tagRules'").first ?? TagRules()
    }
    private func saveRules(_ rules: TagRules) throws {
        let stmt = try statement("INSERT INTO preferences(key,payload) VALUES('tagRules',?) ON CONFLICT(key) DO UPDATE SET payload=excluded.payload")
        defer { sqlite3_finalize(stmt) }; try bind(rules, to: 1, in: stmt); try finish(stmt)
    }
    /// Catalog, memberships, aliases and FTS change together or not at all.
    public func renameTag(_ old: String, to raw: String) throws {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 60, !name.contains(",") else { throw LibraryError.database("Enter a tag name of 1–60 characters without commas") }
        try transaction {
            var rules = try tagRules(); rules.rename(old, to: name)
            try saveRules(rules)
            var catalog = try tagCatalog()
            catalog.names = rules.apply(catalog.names + [name], automatic: false)
            try saveTagCatalog(catalog)
            for var item in try screenshots() {
                let revised = rules.apply(item.tags, automatic: !item.manualTags)
                if revised != item.tags { item.tags = revised; try write(item) }
            }
        }
    }
    public func hideAutomaticTag(_ name: String) throws {
        try transaction {
            var rules = try tagRules(); rules.hiddenAutomatic.insert(ContentTags.key(rules.resolved(name)))
            try saveRules(rules)
            for var item in try screenshots() where !item.manualTags {
                let revised = rules.apply(item.tags, automatic: true)
                if revised != item.tags { item.tags = revised; try write(item) }
            }
        }
    }
    public func restoreAutomaticTag(_ name: String) throws {
        var rules = try tagRules(); rules.hiddenAutomatic.remove(ContentTags.key(name)); try saveRules(rules)
    }
    public func nextPending() throws -> Screenshot? {
        try payloads(Screenshot.self, sql: "SELECT payload FROM screenshots WHERE ocr_status='pending' AND NOT EXISTS (SELECT 1 FROM cleanup_paths WHERE screenshot_id=screenshots.id) ORDER BY rowid LIMIT 1").first
    }
    public func recoverProcessing() throws {
        for item in try payloads(Screenshot.self, sql: "SELECT payload FROM screenshots WHERE ocr_status='processing'") {
            try setProcessing(item.id, status: "pending")
        }
    }
    public func saveSettings(_ settings: AutomationSettings) throws {
        let stmt = try statement("INSERT INTO preferences(key,payload) VALUES('automation',?) ON CONFLICT(key) DO UPDATE SET payload=excluded.payload")
        defer { sqlite3_finalize(stmt) }; try bind(settings, to: 1, in: stmt); try finish(stmt)
    }
    public func settings() throws -> AutomationSettings? {
        try payloads(AutomationSettings.self, sql: "SELECT payload FROM preferences WHERE key='automation'").first
    }
    public func onboarding() throws -> OnboardingState? {
        try payloads(OnboardingState.self, sql: "SELECT payload FROM preferences WHERE key='onboarding'").first
    }
    public func needsOnboarding() throws -> Bool {
        if let state = try onboarding() { return !state.completed }
        return try screenshots().isEmpty && permissions().isEmpty
    }
    public func saveOnboarding(_ state: OnboardingState) throws {
        let stmt = try statement("INSERT INTO preferences(key,payload) VALUES('onboarding',?) ON CONFLICT(key) DO UPDATE SET payload=excluded.payload")
        defer { sqlite3_finalize(stmt) }; try bind(state, to: 1, in: stmt); try finish(stmt)
    }
    /// Setup and automation defaults become effective together, never as a partial completion.
    public func finishOnboarding(_ state: OnboardingState, settings: AutomationSettings) throws {
        try transaction {
            if settings.intakeEnabled {
                let folders = try permissions().filter(\.isFolder).map { CleanupService.pathKey($0.path) }
                guard !settings.watchedPaths.isEmpty, settings.watchedPaths.allSatisfy({ path in
                    let candidate = CleanupService.pathKey(path)
                    return folders.contains { candidate == $0 || candidate.hasPrefix($0 + "/") }
                }) else { throw LibraryError.database("Choose and allow access to a screenshot folder, or continue with manual import.") }
            }
            var completed = state; completed.completed = true; completed.step = 2
            try saveSettings(settings); try saveOnboarding(completed)
        }
    }
    public func searchIDs(_ query: String) throws -> Set<UUID> {
        // Quote each word to prevent user input from becoming FTS syntax.
        let words = query.split(whereSeparator: { $0.isWhitespace }).map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*" }
        guard !words.isEmpty else { return [] }
        let stmt = try statement("SELECT id FROM search WHERE search MATCH ?")
        defer { sqlite3_finalize(stmt) }; bind(words.joined(separator: " AND "), to: 1, in: stmt)
        var ids: Set<UUID> = []
        while true {
            let result = sqlite3_step(stmt)
            if result == SQLITE_DONE { return ids }
            guard result == SQLITE_ROW, let raw = sqlite3_column_text(stmt, 0) else { throw LibraryError.database("Search failed") }
            if let id = UUID(uuidString: String(cString: raw)) { ids.insert(id) }
        }
    }
    public func save(_ collection: Collection) throws {
        let stmt = try statement("INSERT INTO collections(id,payload) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload")
        defer { sqlite3_finalize(stmt) }
        bind(collection.id.uuidString, to: 1, in: stmt); try bind(collection, to: 2, in: stmt); try finish(stmt)
    }
    public func cleanupReservedPaths() throws -> Set<String> {
        let stmt = try statement("SELECT path FROM cleanup_paths"); defer { sqlite3_finalize(stmt) }
        var paths: Set<String> = []
        while sqlite3_step(stmt) == SQLITE_ROW { if let value = sqlite3_column_text(stmt, 0) { paths.insert(String(cString: value)) } }
        return paths
    }
    public func isCleanupReserved(_ path: String) throws -> Bool {
        let stmt = try statement("SELECT 1 FROM cleanup_paths WHERE path=? LIMIT 1"); defer { sqlite3_finalize(stmt) }
        bind(CleanupService.pathKey(path), to: 1, in: stmt)
        return sqlite3_step(stmt) == SQLITE_ROW
    }
    public func cleanupOperations() throws -> [CleanupOperation] {
        try payloads(CleanupOperation.self, sql: "SELECT payload FROM cleanup_operations ORDER BY created DESC")
    }
    public func cleanupOperation(_ id: UUID) throws -> CleanupOperation? { try cleanupOperations().first { $0.id == id } }
    private func writeCleanup(_ operation: CleanupOperation) throws {
        let stmt = try statement("INSERT INTO cleanup_operations(id,created,payload) VALUES(?,?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload")
        defer { sqlite3_finalize(stmt) }; bind(operation.id.uuidString, to: 1, in: stmt)
        sqlite3_bind_double(stmt, 2, operation.createdAt.timeIntervalSince1970); try bind(operation, to: 3, in: stmt); try finish(stmt)
    }
    public func beginCleanup(_ operation: CleanupOperation, undo: Bool = false) throws {
        try transaction {
            let previous = try cleanupOperation(operation.id)
            if undo {
                guard previous != nil else { throw CleanupError.problem("The operation is no longer in history.") }
            } else if previous != nil { throw CleanupError.problem("This preview was already used. Create a new preview.") }
            for entry in operation.entries where entry.phase == .pending {
                if undo {
                    guard previous?.entries.first(where: { $0.id == entry.id })?.canUndo == true else { throw CleanupError.problem("This entry cannot be undone.") }
                }
                guard let item = try record(entry.screenshotID), item.path == entry.from, item.contentHash == entry.expectedHash else {
                    throw CleanupError.problem("A screenshot changed since preview. Create a new preview.")
                }
                for path in entry.reservedPaths {
                    let stmt = try statement("INSERT INTO cleanup_paths(path,screenshot_id,operation_id) VALUES(?,?,?)")
                    defer { sqlite3_finalize(stmt) }; bind(CleanupService.pathKey(path), to: 1, in: stmt)
                    bind(entry.screenshotID.uuidString, to: 2, in: stmt); bind(operation.id.uuidString, to: 3, in: stmt); try finish(stmt)
                }
            }
            try writeCleanup(operation)
        }
    }
    public func checkpointCleanup(_ operation: CleanupOperation, releasing index: Int? = nil) throws {
        try transaction {
            try writeCleanup(operation)
            if let index {
                let stmt = try statement("DELETE FROM cleanup_paths WHERE operation_id=? AND screenshot_id=?")
                defer { sqlite3_finalize(stmt) }; bind(operation.id.uuidString, to: 1, in: stmt)
                bind(operation.entries[index].screenshotID.uuidString, to: 2, in: stmt); try finish(stmt)
            }
        }
    }
    public func commitCleanupLocation(_ operation: CleanupOperation, index: Int, path: String) throws {
        let entry = operation.entries[index]
        guard [entry.originalPath, entry.destinationPath, entry.holdingPath].contains(path) else { throw CleanupError.problem("Invalid recovery location.") }
        try transaction {
            let identity = try CleanupService.identity(path)
            let expected = path == entry.to ? entry.copyIdentity : entry.sourceIdentity
            if let expected, identity != expected { throw CleanupError.problem("The verified file was replaced before its location could be saved.") }
            guard var item = try record(entry.screenshotID), item.contentHash == entry.expectedHash else { throw CleanupError.problem("The screenshot record changed; file locations need review.") }
            guard [entry.originalPath, entry.destinationPath, entry.holdingPath].contains(item.path) else { throw CleanupError.problem("The screenshot was relocated outside this operation.") }
            let oldPath = item.path; item.path = path
            try write(item); try writeCleanup(operation)
            if oldPath != path {
                let stmt = try statement("DELETE FROM access WHERE path=?"); defer { sqlite3_finalize(stmt) }
                bind(oldPath, to: 1, in: stmt); try finish(stmt)
            }
        }
    }
    public func groupReviewHistory() throws -> GroupReviewHistory {
        try payloads(GroupReviewHistory.self, sql: "SELECT payload FROM preferences WHERE key='groupReviews'").first ?? GroupReviewHistory()
    }
    private func saveHistory(_ history: GroupReviewHistory) throws {
        let stmt = try statement("INSERT INTO preferences(key,payload) VALUES('groupReviews',?) ON CONFLICT(key) DO UPDATE SET payload=excluded.payload")
        defer { sqlite3_finalize(stmt) }; try bind(history, to: 1, in: stmt); try finish(stmt)
    }
    public func dismissSuggestion(_ group: AutomaticGroup) throws {
        var history = try groupReviewHistory(); history.record(group); try saveHistory(history)
    }
    public func resetGroupReviews(settings: AutomationSettings) throws {
        try transaction { try saveHistory(GroupReviewHistory()); try saveSettings(settings) }
    }
    public func acceptGroup(_ group: AutomaticGroup, collection: Collection, includedIDs: Set<UUID>? = nil) throws {
        let included = includedIDs ?? Set(group.itemIDs)
        let name = collection.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !included.isEmpty, included.isSubset(of: Set(group.itemIDs)), !name.isEmpty, name.count <= 120 else {
            throw LibraryError.database("Choose at least one screenshot from this group and a collection name of 1–120 characters")
        }
        try transaction {
            // Validate all records before saving anything. Metadata, FTS and decision commit together.
            var selected: [Screenshot] = []
            for id in included.sorted(by: { $0.uuidString < $1.uuidString }) {
                guard let item = try record(id) else { throw LibraryError.database("A selected screenshot is no longer in the library. Review the group again.") }
                selected.append(item)
            }
            try save(Collection(id: collection.id, name: name))
            for var item in selected {
                if !item.collections.contains(collection.id) { item.collections.append(collection.id) }
                try write(item)
            }
            var history = try groupReviewHistory(); history.record(group, collectionID: collection.id); try saveHistory(history)
        }
    }
    public func save(_ access: SavedAccess) throws {
        let stmt = try statement("INSERT INTO access(path,payload) VALUES(?,?) ON CONFLICT(path) DO UPDATE SET payload=excluded.payload")
        defer { sqlite3_finalize(stmt) }
        bind(access.path, to: 1, in: stmt); try bind(access, to: 2, in: stmt); try finish(stmt)
    }
}

// The pointer never escapes LibraryStore. This owner closes it only after actor destruction.
private final class SQLiteConnection: @unchecked Sendable {
    let handle: OpaquePointer?
    init(_ handle: OpaquePointer?) { self.handle = handle }
    deinit { sqlite3_close(handle) }
}
