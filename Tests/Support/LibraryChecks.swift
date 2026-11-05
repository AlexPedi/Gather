import Foundation
import ImageIO
import CoreGraphics
import GatherCore

@MainActor public final class LibraryChecks {
    public init() {}
    var directories: [URL] = []
    public func clean() { for url in directories { try? FileManager.default.removeItem(at: url) } }
    func temporary() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("GatherTests-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        directories.append(url)
        return url
    }
    func image(at url: URL) throws {
        let context = try unwrap(CGContext(data: nil, width: 1600, height: 900, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(red: 0.5, green: 0.3, blue: 0.8, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 1600, height: 900))
        let destination = try unwrap(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try unwrap(context.makeImage()), nil)
        try checkTrue(CGImageDestinationFinalize(destination))
    }
    public func testReimportPreservesIdentityAndManualEditsAcrossRelaunch() async throws {
        let root = try temporary(); let file = root.appendingPathComponent("Screenshot.png")
        try image(at: file)
        let original = try Data(contentsOf: file)
        let db = root.appendingPathComponent("Library.sqlite")
        let store = try LibraryStore(url: db); let importer = Importer(store: store)
        let first = await importer.run(urls: [file], sourceFolder: root.path) { _, _ in }
        try checkEqual(first.imported, 1)
        let imported = try await store.screenshots()
        var item = try unwrap(imported.first)
        let id = item.id
        item.title = "My project"; item.manualTitle = true; item.category = .design; item.manualCategory = true
        item.tags = ["Reference"]; item.manualTags = true; item.favorite = true
        let collection = Collection(name: "Ideas")
        try await store.save(collection); item.collections = [collection.id]; try await store.update(item)
        let second = await importer.run(urls: [file, file], sourceFolder: root.path) { _, _ in }
        try checkEqual(second.unchanged, 2)
        let reopened = try LibraryStore(url: db)
        let records = try await reopened.screenshots()
        try checkEqual(records.count, 1)
        try checkEqual(records.first?.id, id)
        try checkEqual(records.first?.title, "My project")
        try checkEqual(records.first?.tags, ["Reference"])
        try checkEqual(records.first?.category, .design)
        try checkEqual(records.first?.manualTitle, true)
        try checkEqual(records.first?.manualCategory, true)
        try checkEqual(records.first?.manualTags, true)
        try checkEqual(records.first?.favorite, true)
        try checkEqual(records.first?.collections, [collection.id])
        try checkEqual(try Data(contentsOf: file), original, "Import must never modify originals")
    }
    public func testIdenticalContentAtDifferentPathsRemainsReviewable() async throws {
        let root = try temporary(); let a = root.appendingPathComponent("a.png"); let b = root.appendingPathComponent("b.png")
        try image(at: a); try FileManager.default.copyItem(at: a, to: b)
        let store = try LibraryStore(url: root.appendingPathComponent("db.sqlite"))
        let importer = Importer(store: store)
        let report = await importer.run(urls: [a, b], sourceFolder: root.path) { _, _ in }
        try checkEqual(report.imported, 2)
        let records = try await store.screenshots()
        try checkEqual(Set(records.map(\.contentHash)).count, 1)
        try checkEqual(Set(records.map(\.id)).count, 2)
    }
    public func testCorruptFileDoesNotStopImportAndThumbnailIsBounded() async throws {
        let root = try temporary(); let corrupt = root.appendingPathComponent("broken.png"); let valid = root.appendingPathComponent("Screen Shot.png")
        try Data("not an image".utf8).write(to: corrupt); try image(at: valid)
        let store = try LibraryStore(url: root.appendingPathComponent("db.sqlite"))
        let importer = Importer(store: store)
        let report = await importer.run(urls: [corrupt, valid], sourceFolder: root.path) { _, _ in }
        try checkEqual(report.imported, 1); try checkEqual(report.errors.count, 1)
        let thumb = try ImageService.downsample(valid, pixels: 240)
        try checkLessThanOrEqual(max(thumb.width, thumb.height), 240)
        let records = try await store.screenshots()
        let record = try unwrap(records.first)
        let cacheDirectory = root.appendingPathComponent("cache")
        let cache = try ThumbnailCache(directory: cacheDirectory)
        let first = try await cache.thumbnail(for: record, pixels: 240)
        let second = try await cache.thumbnail(for: record, pixels: 240)
        try checkEqual(first.width, second.width)
        func rgba(_ image: CGImage) throws -> Data {
            let context = try unwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return Data(bytes: try unwrap(context.data), count: image.width * image.height * 4)
        }
        try checkEqual(try rgba(first), try rgba(second))
        let original = try await cache.original(for: record)
        try checkEqual(original.width, record.width)
        try checkEqual(original.height, record.height)
        let source = try unwrap(CGImageSourceCreateWithURL(valid as CFURL, nil))
        try checkEqual(try rgba(original), try rgba(try unwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))))
        // Older JPEG caches must be ignored, including on first access after upgrade.
        let stale = cacheDirectory.appendingPathComponent("\(record.thumbnailKey)-180.jpg")
        try Data("obsolete JPEG fixture".utf8).write(to: stale)
        let fresh = try await cache.thumbnail(for: record, pixels: 180)
        try checkLessThanOrEqual(max(fresh.width, fresh.height), 180)
        try checkTrue(FileManager.default.fileExists(atPath: cacheDirectory.appendingPathComponent("lossless-v1-\(record.thumbnailKey)-240.png").path))
        let wideURL = root.appendingPathComponent("wide.png")
        let wideContext = try unwrap(CGContext(data: nil, width: 9001, height: 2, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        wideContext.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 0.5))
        wideContext.fill(CGRect(x: 0, y: 0, width: 9001, height: 2))
        let wideImage = try unwrap(wideContext.makeImage())
        let destination = try unwrap(CGImageDestinationCreateWithURL(wideURL as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, wideImage, nil)
        try checkTrue(CGImageDestinationFinalize(destination))
        let wideOriginal = try ImageService.original(wideURL)
        try checkEqual(wideOriginal.width, 9001)
        try checkEqual(wideOriginal.height, 2)
        try checkEqual(try rgba(wideOriginal), try rgba(wideImage))
        try checkTrue(ImageService.likelyScreenshot(valid))
        try checkFalse(ImageService.likelyScreenshot(root.appendingPathComponent("holiday.jpg")))
        let candidates = try ImageService.candidates(in: root, screenshotsOnly: true)
        try checkEqual(candidates.map { $0.resolvingSymlinksInPath().path }, [valid.resolvingSymlinksInPath().path])
    }
}

struct CheckFailure: Error { let message: String }
func unwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw CheckFailure(message: "Unexpected nil") }
    return value
}
func checkEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) throws {
    guard a == b else { throw CheckFailure(message: "Equality failed at \(file):\(line). \(message)") }
}
func checkLessThanOrEqual<T: Comparable>(_ a: T, _ b: T) throws { guard a <= b else { throw CheckFailure(message: "Thumbnail exceeds its bound") } }
func checkTrue(_ value: Bool) throws { guard value else { throw CheckFailure(message: "Expected true") } }
func checkFalse(_ value: Bool) throws { guard !value else { throw CheckFailure(message: "Expected false") } }

