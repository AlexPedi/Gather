import Foundation

/// A serial actor bounds image hashing and metadata work to one file at a time.
public actor Importer {
    let store: LibraryStore
    public init(store: LibraryStore) { self.store = store }
    public func run(urls: [URL], sourceFolder: String?, automatic: Bool = false, progress: @Sendable (Int, Int) async -> Void) async -> ImportReport {
        var report = ImportReport()
        var known: [String: Screenshot]
        do { known = Dictionary(uniqueKeysWithValues: try await store.screenshots().map { ($0.path, $0) }) }
        catch { report.errors.append(error.localizedDescription); return report }
        for (index, url) in urls.enumerated() {
            if Task.isCancelled { break }
            do {
                let path = url.standardizedFileURL.path
                if try await store.isCleanupReserved(path) { report.deferredPaths.insert(path); continue }
                let item = try ImageService.inspect(url, sourceFolder: sourceFolder ?? url.deletingLastPathComponent().path)
                if let existing = known[path] {
                    if existing.contentHash == item.contentHash { report.unchanged += 1 }
                    else {
                        _ = try ImageService.downsample(url, pixels: 32)
                        try await store.refreshSource(existing.id, source: item)
                        var revised = item; revised.id = existing.id
                        known[path] = revised; report.imported += 1
                    }
                } else {
                    _ = try ImageService.downsample(url, pixels: 32)
                    if try await store.insert(item, automatic: automatic) { report.imported += 1; known[path] = item }
                    else {
                        if try await store.isCleanupReserved(path) { report.deferredPaths.insert(path) }
                        else { report.unchanged += 1 }
                    }
                }
            } catch { report.errors.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            await progress(index + 1, urls.count)
        }
        return report
    }
}
