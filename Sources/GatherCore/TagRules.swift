import Foundation

public struct TagRules: Codable, Sendable {
    public var aliases: [String: String] = [:]
    public var hiddenAutomatic: Set<String> = []
    public init() {}
    public func resolved(_ name: String) -> String {
        var value = name; var visited: Set<String> = []
        while let target = aliases[ContentTags.key(value)], visited.insert(ContentTags.key(value)).inserted { value = target }
        return value
    }
    public func apply(_ tags: [String], automatic: Bool) -> [String] {
        ContentTags.normalize(tags.map(resolved).filter { !automatic || !hiddenAutomatic.contains(ContentTags.key($0)) })
    }
    public mutating func rename(_ old: String, to new: String) {
        let oldKey = ContentTags.key(old), newKey = ContentTags.key(new)
        let previous = self
        aliases.removeValue(forKey: newKey)
        for (source, value) in aliases where ContentTags.key(previous.resolved(value)) == oldKey { aliases[source] = new }
        aliases[oldKey] = new
        if hiddenAutomatic.remove(oldKey) != nil { hiddenAutomatic.insert(newKey) }
    }
}
