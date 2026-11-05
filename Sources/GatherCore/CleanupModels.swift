import Foundation

public enum CleanupDirection: String, Codable, Sendable { case move, undo }
public enum CleanupPhase: String, Codable, Sendable {
    case pending, copying, publishing, published, catalogued, removingSource, complete, failed, needsAttention, skipped
    public var isActive: Bool { [.pending, .copying, .publishing, .published, .catalogued, .removingSource].contains(self) }
}
public struct FileIdentity: Codable, Sendable, Equatable {
    public var device: UInt64
    public var inode: UInt64
}
public struct CleanupEntry: Codable, Sendable, Identifiable {
    public var id = UUID()
    public var screenshotID: UUID
    public var title: String
    public var originalPath: String
    public var destinationPath: String
    public var expectedHash: String
    public var direction: CleanupDirection = .move
    public var phase: CleanupPhase = .pending
    public var detail: String?
    public var sourceIdentity: FileIdentity?
    public var copyIdentity: FileIdentity?
    public var from: String { direction == .move ? originalPath : destinationPath }
    public var to: String { direction == .move ? destinationPath : originalPath }
    public var stagingPath: String { URL(fileURLWithPath: to).deletingLastPathComponent().appendingPathComponent(".gather-\(id)-\(direction.rawValue).partial").path }
    public var holdingPath: String { URL(fileURLWithPath: from).deletingLastPathComponent().appendingPathComponent(".gather-\(id)-\(direction.rawValue).source").path }
    public var reservedPaths: [String] { [from, to, stagingPath, holdingPath] }
    public var canUndo: Bool { direction == .move && phase == .complete || direction == .undo && phase == .failed }
    public var status: String {
        switch phase {
        case .complete: direction == .move ? "Moved" : "Restored"
        case .failed: direction == .move ? "Move failed" : "Undo failed"
        case .needsAttention: "Needs attention"
        case .skipped: "Skipped"
        default: direction == .move ? "Moving…" : "Restoring…"
        }
    }
}
public struct CleanupOperation: Codable, Sendable, Identifiable {
    public var id = UUID()
    public var createdAt = Date()
    public var destinationFolder: String
    public var entries: [CleanupEntry]
    public var isActive: Bool { entries.contains { $0.phase.isActive } }
    public var canUndo: Bool { entries.contains(where: \.canUndo) }
    public var needsAttention: Bool { entries.contains { $0.phase == .needsAttention } }
    public init(destinationFolder: String, entries: [CleanupEntry]) { self.destinationFolder = destinationFolder; self.entries = entries }
}
public enum CleanupError: LocalizedError {
    case problem(String)
    public var errorDescription: String? { switch self { case .problem(let message): message } }
}
