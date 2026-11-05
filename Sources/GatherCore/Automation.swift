import Foundation
import CryptoKit
import Vision

public struct AutomationSettings: Codable, Sendable {
    public var watchedPaths: [String] = []
    public var indexingEnabled = true
    public var intakeEnabled = true
    public var dismissedGroups: Set<String> = []
    public init() {}
    private enum CodingKeys: String, CodingKey { case watchedPaths, indexingEnabled, intakeEnabled, dismissedGroups }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        watchedPaths = try values.decodeIfPresent([String].self, forKey: .watchedPaths) ?? []
        indexingEnabled = try values.decodeIfPresent(Bool.self, forKey: .indexingEnabled) ?? true
        intakeEnabled = try values.decodeIfPresent(Bool.self, forKey: .intakeEnabled) ?? true
        dismissedGroups = try values.decodeIfPresent(Set<String>.self, forKey: .dismissedGroups) ?? []
    }
}
public struct Suggestion: Sendable {
    public var title: String?
    public var category: Category
    public var tags: [String]
}
public enum Classifier {
    private static let rules: [(Category, [String])] = [
        (.development, ["typescript", "javascript", "github", "stack trace", "exception", "npm", "python", "swift", "api", "localhost", "function", "debug", "error", "xcode"]),
        (.finance, ["premium", "deductible", "coinsurance", "copay", "out-of-pocket", "out of pocket", "insurance", "benefits", "salary", "payroll", "tax", "invoice", "balance", "spending", "budget", "payment", "401k", "hsa", "fsa", "medical plan", "dental", "coverage"]),
        (.travel, ["hotel", "flight", "boarding", "airport", "reservation", "check-in", "itinerary", "airbnb", "booking", "departure", "arrival", "resort"]),
        (.design, ["figma", "typography", "wireframe", "prototype", "design system", "color palette", "dribbble", "behance", "font", "mockup"]),
        (.shopping, ["add to cart", "checkout", "shipping", "order total", "buy now", "shopping cart", "subtotal", "delivery", "product details"]),
        (.home, ["kitchen", "renovation", "floor plan", "living room", "bedroom", "furniture", "interior", "apartment", "mortgage"]),
        (.conversations, ["slack", "messages", "replied", "direct message", "whatsapp", "imessage", "sent a message", "discord", "thread", "channel"]),
        (.work, ["meeting", "project", "deadline", "agenda", "roadmap", "quarterly", "onboarding", "presentation", "team", "milestone"])
    ]
    public static func tokens(_ text: String) -> Set<String> {
        let stop: Set<String> = ["this", "that", "with", "from", "your", "have", "will", "more", "about", "there", "their", "view", "screen", "screenshot", "https", "www", "com", "the", "and", "for", "are", "all", "not", "you"]
        return Set(text.lowercased().components(separatedBy: .alphanumerics.inverted).filter { $0.count > 2 && !stop.contains($0) && $0.rangeOfCharacter(from: .letters) != nil })
    }
    public static func suggest(text: String) -> Suggestion {
        let lower = " " + text.lowercased().components(separatedBy: .alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ") + " "
        let ranked = rules.map { category, words in
            (category, words.filter { word in
                let normalized = word.components(separatedBy: .alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
                return lower.contains(" " + normalized + " ")
            })
        }.sorted { $0.1.count > $1.1.count }
        let best = ranked.first!
        let category: Category = best.1.count >= 2 && best.1.count > ranked[1].1.count ? best.0 : .uncategorized
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let candidate = lines.first { line in
            let words = tokens(line)
            return line.count >= 10 && line.count <= 110 && words.count >= 2 && !line.hasPrefix("http")
        }
        return Suggestion(title: candidate.map { String($0.prefix(85)) }, category: category,
                          tags: ContentTags.suggest(text))
    }
}

public struct AutomaticGroup: Identifiable, Sendable {
    public var id: String
    public var title: String
    public var reason: String
    public var itemIDs: [UUID]
    public var kind: GroupKind
    public var duplicateHash: String?
    public var evidence: [GroupEvidence]
    public init(id: String, title: String, reason: String, itemIDs: [UUID], kind: GroupKind = .related,
                duplicateHash: String? = nil, evidence: [GroupEvidence] = []) {
        self.id = id; self.title = title; self.reason = reason; self.itemIDs = itemIDs
        self.kind = kind; self.duplicateHash = duplicateHash; self.evidence = evidence
    }
    public var sharedWords: [String] {
        var counts: [String: Int] = [:]
        for link in evidence { for word in link.words { counts[word, default: 0] += 1 } }
        return counts.keys.sorted { counts[$0] == counts[$1] ? $0 < $1 : counts[$0, default: 0] > counts[$1, default: 0] }.prefix(8).map { $0 }
    }
}
public enum Grouper {
    public static func groups(_ items: [Screenshot]) -> [AutomaticGroup] {
        var groups: [AutomaticGroup] = []
        func make(_ members: [Screenshot], title: String, reason: String, kind: String, evidence: [GroupEvidence] = []) -> AutomaticGroup {
            let ids = members.map(\.id).sorted { $0.uuidString < $1.uuidString }
            let key = kind + ids.map(\.uuidString).joined()
            let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
            return AutomaticGroup(id: hash, title: title, reason: reason, itemIDs: ids, kind: kind == "duplicates" ? .duplicates : .related, duplicateHash: kind == "duplicates" ? members.first?.contentHash : nil, evidence: evidence)
        }
        for (_, members) in Dictionary(grouping: items, by: \.contentHash) where members.count > 1 {
            groups.append(make(members, title: "Exact duplicates", reason: "Identical file contents · originals kept", kind: "duplicates"))
        }
        let ordered = items.filter { $0.ocrStatus == "complete" && !$0.extractedText.isEmpty }.sorted { $0.captureDate < $1.captureDate }
        let wordSets = ordered.map { Set(Classifier.tokens($0.extractedText).filter { ContentTags.isUseful($0) }) }
        var parent = Array(ordered.indices)
        var links: [GroupEvidence] = []
        func root(_ n: Int) -> Int { var p = n; while parent[p] != p { p = parent[p] }; return p }
        for i in ordered.indices {
            // Bounded comparisons within a 45-minute capture session; time alone is insufficient.
            for j in max(0, i - 40)..<i {
                guard ordered[i].captureDate.timeIntervalSince(ordered[j].captureDate) <= 45 * 60,
                      ordered[i].contentHash != ordered[j].contentHash else { continue }
                let common = wordSets[i].intersection(wordSets[j]).count
                let union = wordSets[i].union(wordSets[j]).count
                let similarity = Double(common) / Double(max(1, union))
                if common >= 4 && similarity >= 0.22 {
                    parent[root(i)] = root(j)
                    let words = wordSets[i].intersection(wordSets[j]).filter { ContentTags.isUseful($0) }.sorted()
                    links.append(GroupEvidence(left: ordered[j].id, right: ordered[i].id, words: Array(words.prefix(12)), similarity: similarity,
                                               captureGap: ordered[i].captureDate.timeIntervalSince(ordered[j].captureDate)))
                }
            }
        }
        var clusters: [Int: [Screenshot]] = [:]
        for i in ordered.indices { clusters[root(i), default: []].append(ordered[i]) }
        let roots = Dictionary(uniqueKeysWithValues: ordered.indices.map { (ordered[$0].id, root($0)) })
        var clusterLinks: [Int: [GroupEvidence]] = [:]
        for link in links { if let key = roots[link.left] { clusterLinks[key, default: []].append(link) } }
        for (cluster, members) in clusters where members.count > 1 {
            let categories = Set(members.map(\.category))
            let title = categories.count == 1 && categories.first != .uncategorized ? "Related \(members[0].category.rawValue.lowercased()) screenshots" : "Related screenshots"
            let evidence = (clusterLinks[cluster] ?? []).sorted { $0.similarity == $1.similarity ? $0.id < $1.id : $0.similarity > $1.similarity }
            groups.append(make(members, title: title, reason: "Shared text · captured within a nearby session", kind: "related", evidence: evidence))
        }
        return groups.sorted { $0.id < $1.id }
    }
}

public actor OCRWorker {
    private let store: LibraryStore
    private var running = false
    public init(store: LibraryStore) { self.store = store }
    public func processNext() async throws -> Bool {
        guard !running else { return false }
        running = true; defer { running = false }
        guard let item = try await store.nextPending() else {
            guard let indexed = try await store.nextTagsPending() else { return false }
            let tags = ContentTags.suggest(indexed.extractedText)
            try await store.completeTags(indexed.id, hash: indexed.contentHash, tags: tags)
            return true
        }
        try await store.setProcessing(item.id, status: "processing", hash: item.contentHash)
        do {
            let text = try Self.recognize(URL(fileURLWithPath: item.path))
            try await store.completeOCR(item.id, hash: item.contentHash, text: text)
        } catch {
            let latest = try await store.record(item.id)
            if latest?.path != item.path { try await store.setProcessing(item.id, status: "pending", hash: item.contentHash) }
            else { try await store.setProcessing(item.id, status: "failed", error: error.localizedDescription, hash: item.contentHash) }
        }
        return true
    }
    public static func recognize(_ url: URL) throws -> String {
        let image = try ImageService.downsample(url, pixels: 3200)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first, text.confidence >= 0.3 else { return nil }
            return text.string
        }.joined(separator: "\n")
    }
}
