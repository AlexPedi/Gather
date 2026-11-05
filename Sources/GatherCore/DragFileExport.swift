import Foundation
import UniformTypeIdentifiers

/// Each drag exports a verified copy, so a receiving app can never move our source.
public actor DragFileExport {
    private let item: Screenshot
    private let directory: URL
    private var cached: URL?
    public init(item: Screenshot, directory: URL) { self.item = item; self.directory = directory }
    public func file() throws -> URL {
        if let cached, (try? CleanupService.identity(cached.path)) != nil,
           (try? ImageService.hash(cached)) == item.contentHash { return cached }
        let output = try Self.copy(item: item, directory: directory)
        cached = output
        return output
    }
    public nonisolated static func copy(item: Screenshot, directory: URL) throws -> URL {
        let source = URL(fileURLWithPath: item.path)
        _ = try CleanupService.identity(source.path)
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let output = folder.appendingPathComponent(source.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: source, to: output)
            _ = try CleanupService.identity(output.path)
            guard try ImageService.hash(output) == item.contentHash else {
                throw CleanupError.problem("This image changed since it was added. Let Gather refresh it before dragging again.")
            }
            return output
        } catch { try? FileManager.default.removeItem(at: folder); throw error }
    }
}

public enum DragFileProvider {
    public static func make(item: Screenshot, directory: URL, onFailure: @escaping @Sendable (String) -> Void = { _ in }) -> NSItemProvider {
        let export = DragFileExport(item: item, directory: directory)
        let provider = NSItemProvider()
        provider.suggestedName = URL(fileURLWithPath: item.path).lastPathComponent
        let type = UTType(filenameExtension: URL(fileURLWithPath: item.path).pathExtension) ?? .data
        // Image-aware destinations can request the original encoded image format.
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { completion in
            Task {
                do { completion(try await export.file(), false, nil) }
                catch { onFailure(error.localizedDescription); completion(nil, false, error) }
            }
            return nil
        }
        // Finder and file-attachment destinations need a file URL, also pointing only at the copy.
        provider.registerObject(ofClass: NSURL.self, visibility: .all) { completion in
            Task {
                do { completion(try await export.file() as NSURL, nil) }
                catch { onFailure(error.localizedDescription); completion(nil, error) }
            }
            return nil
        }
        provider.registerDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier, visibility: .all) { completion in
            Task {
                do { completion(try await export.file().absoluteString.data(using: .utf8), nil) }
                catch { onFailure(error.localizedDescription); completion(nil, error) }
            }
            return nil
        }
        return provider
    }
}
