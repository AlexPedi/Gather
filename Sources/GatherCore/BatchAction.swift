import Foundation

public enum BatchAction: Sendable {
    case favorite(Bool)
    case addTag(String)
    case removeTag(String)
    case addToCollection(UUID)
}
