import Foundation

public enum Category: String, CaseIterable, Codable, Sendable {
    case work = "Work", design = "Design", development = "Development", travel = "Travel"
    case finance = "Finance", shopping = "Shopping", home = "Home", conversations = "Conversations"
    case uncategorized = "Uncategorized"
}

public struct Screenshot: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID = UUID()
    public var path: String
    public var originalFilename: String
    public var sourceFolder: String
    public var captureDate: Date
    public var importDate: Date = Date()
    public var fileSize: Int64
    public var width: Int
    public var height: Int
    public var title: String
    public var category: Category = .uncategorized
    public var tags: [String] = []
    public var extractedText = ""
    public var ocrStatus = "pending"
    public var favorite = false
    public var inbox = true
    public var collections: [UUID] = []
    public var contentHash: String
    public var thumbnailKey: String
    public var processingError: String?
    public var retryCount = 0
    public var manualTitle = false
    public var manualCategory = false
    public var manualTags = false
    public var taggingVersion: Int?
    public init(path: String, sourceFolder: String, captureDate: Date, fileSize: Int64,
                width: Int, height: Int, contentHash: String) {
        self.path = path
        self.originalFilename = URL(fileURLWithPath: path).lastPathComponent
        self.sourceFolder = sourceFolder
        self.captureDate = captureDate
        self.fileSize = fileSize
        self.width = width
        self.height = height
        self.contentHash = contentHash
        self.thumbnailKey = contentHash
        self.title = "Screenshot · " + captureDate.formatted(date: .abbreviated, time: .shortened)
    }
}

public struct Collection: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var name: String
    public init(id: UUID = UUID(), name: String) { self.id = id; self.name = name }
}

public struct SavedAccess: Codable, Sendable, Identifiable {
    public var id: String { path }
    public var path: String
    public var bookmark: Data
    public var isFolder: Bool
    public init(path: String, bookmark: Data, isFolder: Bool) {
        self.path = path; self.bookmark = bookmark; self.isFolder = isFolder
    }
}

public struct ImportReport: Sendable {
    public var imported = 0
    public var unchanged = 0
    public var deferredPaths: Set<String> = []
    public var errors: [String] = []
    public init() {}
}

public enum LibraryError: LocalizedError {
    case database(String), invalidImage(String), permission(String)
    public var errorDescription: String? {
        switch self {
        case .database(let message): "Library database: \(message)"
        case .invalidImage(let name): "Cannot read image: \(name)"
        case .permission(let path): "Access unavailable for \(path). Use Grant Access to select it again."
        }
    }
}
