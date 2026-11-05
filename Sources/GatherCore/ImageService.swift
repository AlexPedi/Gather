import Foundation
import ImageIO
import CryptoKit
import CoreGraphics

public enum ImageService {
    public static let extensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "webp"]
    public static func isImage(_ url: URL) -> Bool { extensions.contains(url.pathExtension.lowercased()) }
    public static func likelyScreenshot(_ url: URL) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent.lowercased()
        if ["screenshot", "screen shot", "screen capture", "スクリーンショット", "capture d’écran", "captura de pantalla", "bildschirmfoto"].contains(where: name.contains) { return true }
        // Spotlight's screenshot flag covers renamed captures when metadata is available.
        let item = MDItemCreate(kCFAllocatorDefault, url.path as CFString)
        if let item, let value = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString) as? Bool { return value }
        return false
    }
    public static func candidates(in folder: URL, screenshotsOnly: Bool) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            .filter { url in
                isImage(url) && (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true && (!screenshotsOnly || likelyScreenshot(url))
            }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    public static func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public static func inspect(_ url: URL, sourceFolder: String) throws -> Screenshot {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int, width > 0, height > 0 else {
            throw LibraryError.invalidImage(url.lastPathComponent)
        }
        let values = try url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey, .fileSizeKey])
        var date = values.creationDate ?? values.contentModificationDate ?? Date()
        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any],
           let raw = exif[kCGImagePropertyExifDateTimeOriginal] as? String {
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
            date = formatter.date(from: raw) ?? date
        }
        return Screenshot(path: url.standardizedFileURL.path, sourceFolder: sourceFolder, captureDate: date,
                          fileSize: Int64(values.fileSize ?? 0), width: width, height: height, contentHash: try hash(url))
    }
    public static func original(_ url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
            throw LibraryError.invalidImage(url.lastPathComponent)
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        if let orientation = properties?[kCGImagePropertyOrientation] as? Int, orientation != 1 {
            return try downsample(url, pixels: max(image.width, image.height))
        }
        return image
    }
    public static func downsample(_ url: URL, pixels: Int) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw LibraryError.invalidImage(url.lastPathComponent) }
        return image
    }
}

// CoreServices supplies the public Spotlight metadata API, available before macOS 14.
import CoreServices

public actor ThumbnailCache {
    private let directory: URL
    public init(directory: URL) throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    public func original(for item: Screenshot) throws -> CGImage {
        try ImageService.original(URL(fileURLWithPath: item.path))
    }
    public func thumbnail(for item: Screenshot, pixels: Int = 600) throws -> CGImage {
        let cached = directory.appendingPathComponent("lossless-v1-\(item.thumbnailKey)-\(pixels).png")
        if FileManager.default.fileExists(atPath: cached.path), let image = try? ImageService.downsample(cached, pixels: pixels) { return image }
        let image = try ImageService.downsample(URL(fileURLWithPath: item.path), pixels: pixels)
        guard let destination = CGImageDestinationCreateWithURL(cached as CFURL, "public.png" as CFString, 1, nil) else { return image }
        CGImageDestinationAddImage(destination, image, nil)
        if !CGImageDestinationFinalize(destination) { try? FileManager.default.removeItem(at: cached) }
        return image
    }
}
