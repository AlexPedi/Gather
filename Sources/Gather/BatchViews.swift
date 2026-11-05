import SwiftUI
import GatherCore

struct BatchActionBar: View {
    @Bindable var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(model.visibleBatchIDs.count) selected").font(.callout.weight(.semibold))
                Spacer()
                Button("Select All") { model.batchSelection = Set(model.visible.map(\.id)) }
                Button("Clear") { model.batchSelection = [] }.disabled(model.batchSelection.isEmpty)
            }
            HStack {
                Menu("Favorites") {
                    Button("Add Favorites") { model.applyBatch(.favorite(true)) }
                    Button("Remove Favorites") { model.applyBatch(.favorite(false)) }
                }
                Button("Delete…", role: .destructive) { model.requestDeletion(model.visibleBatchIDs) }.disabled(!model.canDelete)
                Button("Edit Tags…") { model.showBatchTags = true }
                Menu("Add to Collection") {
                    if model.collections.isEmpty { Text("Create a collection from the sidebar first") }
                    ForEach(model.collections) { collection in
                        Button(collection.name) { model.applyBatch(.addToCollection(collection.id)) }
                    }
                }
            }.disabled(model.visibleBatchIDs.isEmpty || model.batchBusy)
            if model.batchBusy { HStack { ProgressView().controlSize(.small); Text("Updating screenshots…").font(.caption) } }
        }.padding(12).background(GatherTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct BatchTagsView: View {
    @Bindable var model: AppModel
    @ViewState<String> private var tag = ""
    @ViewState<Bool> private var removing = false
    @Environment(\.dismiss) private var dismiss
    private var name: String { tag.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Edit Tags for \(model.visibleBatchIDs.count) Screenshots").font(.title2.bold())
            Picker("Action", selection: $removing) { Text("Add tag").tag(false); Text("Remove tag").tag(true) }.pickerStyle(.segmented)
            TextField("Tag name", text: $tag).textFieldStyle(.roundedBorder)
            Menu("Choose Existing Tag") {
                ForEach(model.availableTags, id: \.self) { name in Button(name) { tag = name } }
            }.disabled(model.availableTags.isEmpty)
            Text("Other tags are preserved. Edited tag lists become manual so automatic suggestions won’t replace your changes.").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if model.batchBusy { ProgressView().controlSize(.small) }
                Button(removing ? "Remove from Selected" : "Add to Selected") { model.applyBatch(removing ? .removeTag(name) : .addTag(name)) }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(name.isEmpty || name.count > 60 || name.contains(",") || name.contains(where: { $0.isNewline }) || model.visibleBatchIDs.isEmpty)
            }
        }.padding(26).frame(width: 470).disabled(model.batchBusy).interactiveDismissDisabled(model.batchBusy)
            .alert("Batch Update Could Not Finish", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK") { model.error = nil }
            } message: { Text(model.error ?? "") }
    }
}
