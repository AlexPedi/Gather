import Foundation

/// Holds one balanced security scope per saved grant for the app's lifetime.
public actor FileAccess {
    private var active: [String: URL] = [:]
    public init() {}
    deinit {
        for url in active.values { url.stopAccessingSecurityScopedResource() }
    }
    public func grant(_ url: URL, isFolder: Bool) throws -> SavedAccess {
        let started = url.startAccessingSecurityScopedResource()
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            if active[url.path] == nil, started { active[url.path] = url }
            else if started { url.stopAccessingSecurityScopedResource() }
            return SavedAccess(path: url.path, bookmark: bookmark, isFolder: isFolder)
        } catch {
            if started { url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }
    public func restore(_ access: SavedAccess) throws -> SavedAccess {
        var stale = false
        let url = try URL(resolvingBookmarkData: access.bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        let started = url.startAccessingSecurityScopedResource()
        if active[url.path] == nil, started { active[url.path] = url }
        else if started { url.stopAccessingSecurityScopedResource() }
        guard FileManager.default.isReadableFile(atPath: url.path) else { throw LibraryError.permission(access.path) }
        if stale || url.path != access.path {
            return SavedAccess(path: url.path, bookmark: try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil), isFolder: access.isFolder)
        }
        return access
    }
    public func releaseAll() {
        for url in active.values { url.stopAccessingSecurityScopedResource() }
        active.removeAll()
    }
}
