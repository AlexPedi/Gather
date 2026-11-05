import SwiftUI
import GatherCore

enum GatherTheme {
    static let accent = Color(red: 0.43, green: 0.28, blue: 0.91)
    static func color(for category: GatherCore.Category) -> Color {
        switch category {
        case .design, .travel, .conversations: accent
        case .development, .finance: .blue
        case .home: .green
        case .shopping: .orange
        case .work: .indigo
        case .uncategorized: .secondary
        }
    }
}
struct CategoryChip: View {
    let category: GatherCore.Category
    var body: some View {
        Text(category.rawValue).font(.system(size: 11, weight: .medium))
            .foregroundStyle(GatherTheme.color(for: category))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(GatherTheme.color(for: category).opacity(0.12), in: Capsule())
    }
}

struct ContentTagChip: View {
    let name: String
    var body: some View {
        Text(name).font(.system(size: 10, weight: .medium)).lineLimit(1)
            .foregroundStyle(GatherTheme.accent).padding(.horizontal, 7).padding(.vertical, 4)
            .background(GatherTheme.accent.opacity(0.1), in: Capsule())
    }
}
