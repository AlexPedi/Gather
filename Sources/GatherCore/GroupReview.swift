import Foundation

public enum GroupKind: String, Codable, Sendable { case related, duplicates }
public struct GroupEvidence: Identifiable, Sendable {
    public var left: UUID
    public var right: UUID
    public var words: [String]
    public var similarity: Double
    public var captureGap: TimeInterval
    public var id: String { left.uuidString + right.uuidString }
}
public struct GroupDecision: Codable, Sendable {
    public var originalID: String
    public var kind: GroupKind
    public var members: Set<UUID>
    public var duplicateHash: String?
    public var collectionID: UUID?
    public var reviewedAt: Date
    public init(group: AutomaticGroup, collectionID: UUID? = nil) {
        originalID = group.id; kind = group.kind; members = Set(group.itemIDs)
        duplicateHash = group.duplicateHash; self.collectionID = collectionID; reviewedAt = Date()
    }
    public func suppresses(_ group: AutomaticGroup) -> Bool {
        guard group.kind == kind else { return false }
        if group.id == originalID { return true }
        if kind == .duplicates, let duplicateHash, duplicateHash == group.duplicateHash { return true }
        let candidate = Set(group.itemIDs)
        let shared = candidate.intersection(members).count
        guard shared >= 2 else { return false }
        // Ignore small membership changes without suppressing substantially new groups.
        return candidate.isSubset(of: members) || Double(shared) / Double(candidate.union(members).count) >= 0.6
    }
}
public struct GroupReviewHistory: Codable, Sendable {
    public var decisions: [GroupDecision] = []
    public init() {}
    public func suppresses(_ group: AutomaticGroup) -> Bool { decisions.contains { $0.suppresses(group) } }
    public mutating func record(_ group: AutomaticGroup, collectionID: UUID? = nil) {
        decisions.removeAll { $0.originalID == group.id }
        decisions.append(GroupDecision(group: group, collectionID: collectionID))
    }
}
