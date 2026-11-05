import SwiftUI
import GatherCore

struct GroupReviewView: View {
    @Bindable var model: AppModel
    let group: AutomaticGroup
    @Environment(\.dismiss) private var dismiss
    @ViewState<String> private var name: String
    @ViewState<Set<UUID>> private var included: Set<UUID>
    init(model: AppModel, group: AutomaticGroup) {
        self.model = model; self.group = group
        _name = ViewState(initialValue: group.title)
        _included = ViewState(initialValue: Set(group.itemIDs))
    }
    private var members: [Screenshot] {
        model.items.filter { group.itemIDs.contains($0.id) }.sorted { $0.captureDate == $1.captureDate ? $0.id.uuidString < $1.id.uuidString : $0.captureDate < $1.captureDate }
    }
    private var selected: Set<UUID> { included.intersection(Set(members.map(\.id))) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Review Suggested Group", systemImage: group.kind == .duplicates ? "doc.on.doc" : "square.stack").font(.title2.bold())
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(22)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Collection name").font(.headline)
                        TextField("Name this collection", text: $name).textFieldStyle(.roundedBorder).accessibilityLabel("Collection name")
                        Text("Choose which screenshots belong. Excluding an image leaves it in your library.").font(.callout).foregroundStyle(.secondary)
                    }
                    explanation
                    HStack {
                        Text("\(selected.count) of \(members.count) included").font(.headline)
                        Spacer()
                        Button("Include All") { included = Set(members.map(\.id)) }
                        Button("Exclude All") { included.removeAll() }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 14)], spacing: 16) {
                        ForEach(members) { item in
                            VStack(alignment: .leading, spacing: 10) {
                                Button { model.openImage(item) } label: {
                                    ScreenshotImage(item: item, cache: model.cache).frame(height: 145)
                                }.buttonStyle(.plain).accessibilityLabel("Preview \(item.title)")
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(item.title).font(.callout.weight(.medium)).lineLimit(2)
                                    Text(item.captureDate.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                    Toggle(isOn: Binding(get: { included.contains(item.id) }, set: { value in
                                        if value { included.insert(item.id) } else { included.remove(item.id) }
                                    })) { Text(included.contains(item.id) ? "Included" : "Excluded") }
                                        .toggleStyle(.checkbox).accessibilityLabel("Include \(item.title) in collection")
                                }.padding(.horizontal, 10).padding(.bottom, 12)
                            }
                            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(included.contains(item.id) ? GatherTheme.accent.opacity(0.55) : Color.secondary.opacity(0.15)))
                            .opacity(included.contains(item.id) ? 1 : 0.6)
                        }
                    }
                }.padding(22)
            }
            Divider()
            HStack {
                Button("Dismiss Suggestion") { model.dismissGroup(group) }
                    .help("Hide this suggestion and groups with mostly the same screenshots")
                Spacer()
                if model.groupReviewBusy { ProgressView().controlSize(.small) }
                Text("Original files stay in place").font(.caption).foregroundStyle(.secondary)
                Button("Save \(selected.count) as Collection") {
                    model.saveReviewedGroup(group, name: name, includedIDs: selected)
                }.buttonStyle(.borderedProminent).tint(GatherTheme.accent).keyboardShortcut(.defaultAction)
                    .disabled(selected.isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 120)
            }.padding(18)
        }.frame(minWidth: 650, idealWidth: 820, minHeight: 560, idealHeight: 720)
        .disabled(model.groupReviewBusy).interactiveDismissDisabled(model.groupReviewBusy)
        .sheet(item: $model.imagePreview) { item in
            ImagePreviewView(item: item, cache: model.cache)
        }
        .alert("Group Could Not Be Saved", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }

    private var explanation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Why these screenshots?", systemImage: "sparkles").font(.headline)
            if group.kind == .duplicates {
                Text("These separate files have exactly the same contents. Saving or dismissing this group never deletes a copy.").font(.callout)
            } else {
                Text("These screenshots share text and were captured close together. Some are related through another screenshot in the group.").font(.callout)
                if !group.sharedWords.isEmpty {
                    Text("Shared words: " + group.sharedWords.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                DisclosureGroup("Matching connections (\(group.evidence.count))") {
                    ForEach(Array(group.evidence.prefix(20))) { link in
                        let left = members.first { $0.id == link.left }?.title ?? "Screenshot"
                        let right = members.first { $0.id == link.right }?.title ?? "Screenshot"
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(left) ↔ \(right)").font(.caption.weight(.medium))
                            Text("\(Int(link.similarity * 100))% word overlap · \(Int(link.captureGap / 60)) min apart").font(.caption2).foregroundStyle(.secondary)
                        }.padding(.vertical, 5).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if group.evidence.count > 20 { Text("Showing the 20 strongest connections.").font(.caption2).foregroundStyle(.secondary) }
                }
            }
            if let first = members.first, let last = members.last {
                Text("Captured \(first.captureDate.formatted(date: .abbreviated, time: .shortened)) – \(last.captureDate.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(GatherTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
    }
}
