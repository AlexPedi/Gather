import Foundation
import UniformTypeIdentifiers
import GatherCore

extension LibraryChecks {
    public func testOutgoingDragCopiesAndRepresentations() async throws {
        let root = try temporary(), source = root.appendingPathComponent("Screenshot — café.png")
        try image(at: source)
        let bytes = try Data(contentsOf: source)
        let item = try ImageService.inspect(source, sourceFolder: root.path)
        let directory = root.appendingPathComponent("Exports")
        let export = DragFileExport(item: item, directory: directory)
        let file = try await export.file()
        try checkTrue(file.path != source.path)
        try checkEqual(file.lastPathComponent, source.lastPathComponent)
        try checkEqual(try Data(contentsOf: file), bytes)
        try checkEqual(try await export.file(), file)
        // A receiver moving its exported copy must never move the library's original.
        let receiver = root.appendingPathComponent("Received.png")
        try FileManager.default.moveItem(at: file, to: receiver)
        try checkEqual(try Data(contentsOf: source), bytes)
        let next = try await export.file(); try checkTrue(next != file)
        let provider = DragFileProvider.make(item: item, directory: directory)
        try checkEqual(provider.suggestedName, source.lastPathComponent)
        try checkTrue(provider.hasItemConformingToTypeIdentifier(UTType.png.identifier))
        try checkTrue(provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))
        let urlBytes: Data = try await withCheckedThrowingContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
                if let data { continuation.resume(returning: data) }
                else { continuation.resume(throwing: error ?? CleanupError.problem("No file URL data")) }
            }
        }
        let fileURL = URL(string: String(decoding: urlBytes, as: UTF8.self))!
        try checkTrue(fileURL.isFileURL && fileURL.path != source.path)
        try checkEqual(try Data(contentsOf: fileURL), bytes)
        let provided: URL = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadObject(ofClass: NSURL.self) { object, error in
                if let error { continuation.resume(throwing: error) }
                else if let url = object as? URL { continuation.resume(returning: url) }
                else { continuation.resume(throwing: CleanupError.problem("No file URL provided")) }
            }
        }
        try checkTrue(provided.path != source.path)
        try checkEqual(try Data(contentsOf: provided), bytes)
        let represented: Data = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.png.identifier) { url, error in
                do {
                    if let error { throw error }
                    guard let url else { throw CleanupError.problem("No image representation") }
                    continuation.resume(returning: try Data(contentsOf: url))
                } catch { continuation.resume(throwing: error) }
            }
        }
        try checkEqual(represented, bytes)
        try checkEqual(try Data(contentsOf: source), bytes)
        try Data("changed fixture".utf8).write(to: source)
        let stale = DragFileExport(item: item, directory: directory)
        var rejected = false
        do { _ = try await stale.file() } catch { rejected = true }
        try checkTrue(rejected)
        try FileManager.default.removeItem(at: source)
        var missingRejected = false
        do { _ = try await DragFileExport(item: item, directory: directory).file() } catch { missingRejected = true }
        try checkTrue(missingRejected)
    }
}
