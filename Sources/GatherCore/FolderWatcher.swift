import Foundation

public struct FileStamp: Equatable, Sendable {
    public var size: Int
    public var modified: Date
    public init(size: Int, modified: Date) { self.size = size; self.modified = modified }
}
/// Require the same nonempty size/date across two polls before importing.
/// Polling also reconciles after wake and catches events missed while Gather was closed.
public struct StabilityGate: Sendable {
    private var previous: [String: FileStamp] = [:]
    private var imported: [String: FileStamp] = [:]
    public init() {}
    public mutating func ready(_ files: [String: FileStamp]) -> [String] {
        imported = imported.filter { files[$0.key] != nil }
        let ready = files.filter { $0.value.size > 0 && previous[$0.key] == $0.value && imported[$0.key] != $0.value }.map(\.key).sorted()
        previous = files
        return ready
    }
    public mutating func mark(_ path: String, stamp: FileStamp) { imported[path] = stamp }
}
public struct WatchReport: Sendable {
    public var imported = 0
    public var errors: [String] = []
    public init() {}
}
public actor FolderWatcher {
    private var gates: [String: StabilityGate] = [:]
    private var running = false
    private let importer: Importer
    public init(importer: Importer) { self.importer = importer }
    public func reconcile(paths: [String]) async -> WatchReport {
        guard !running else { return WatchReport() }
        running = true; defer { running = false }
        gates = gates.filter { paths.contains($0.key) }
        var report = WatchReport()
        for path in paths {
            do {
                let urls = try ImageService.candidates(in: URL(fileURLWithPath: path), screenshotsOnly: true)
                var stamps: [String: FileStamp] = [:]
                for url in urls {
                    let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                    stamps[url.standardizedFileURL.path] = FileStamp(size: values.fileSize ?? 0, modified: values.contentModificationDate ?? .distantPast)
                }
                var gate = gates[path] ?? StabilityGate()
                let ready = gate.ready(stamps)
                guard !ready.isEmpty else { gates[path] = gate; continue }
                let result = await importer.run(urls: ready.map { URL(fileURLWithPath: $0) }, sourceFolder: path, automatic: true) { _, _ in }
                report.imported += result.imported
                report.errors += result.errors
                // Failures wait for another file change rather than spinning indefinitely.
                for file in ready where !result.deferredPaths.contains(file) { if let stamp = stamps[file] { gate.mark(file, stamp: stamp) } }
                gates[path] = gate
            } catch { report.errors.append("\(path): \(error.localizedDescription)") }
        }
        return report
    }
    public func reset() { gates.removeAll() }
}
