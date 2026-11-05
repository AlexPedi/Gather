import Foundation
import GatherCore

enum Benchmark {
    static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("GatherBenchmark-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try LibraryStore(url: root.appendingPathComponent("Library.sqlite"))
        let clock = ContinuousClock()
        let start = clock.now
        for index in 0..<5000 {
            var record = Screenshot(path: "/benchmark/image-\(index).png", sourceFolder: "/benchmark",
                                    captureDate: Date(timeIntervalSince1970: Double(index)), fileSize: 1_000_000,
                                    width: 2560, height: 1600, contentHash: String(repeating: "a", count: 64))
            record.title = "Screenshot number \(index)"
            try await store.insert(record)
        }
        let written = clock.now
        let items = try await store.screenshots()
        let loaded = clock.now
        let result = items.filter { $0.title.localizedCaseInsensitiveContains("number 42") }.sorted { $0.captureDate > $1.captureDate }
        let queried = clock.now
        guard items.count == 5000, !result.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        print("SYNTHETIC METADATA BENCHMARK · 5,000 records · no image decoding or UI measurement")
        print("Insert: \(written - start); load/decode: \(loaded - written); filter/sort: \(queried - loaded); matches: \(result.count)")
    }
}
