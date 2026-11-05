import SwiftUI
import GatherCore

struct TagManagerView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ViewState<String?> private var selected: String?
    @ViewState<String> private var name = ""
    @ViewState<String> private var destination = ""
    @ViewState<String> private var search = ""
    var body: some View {
        VStack(spacing: 0) {
            HStack { Label("Manage Tags", systemImage: "tag").font(.title2.bold()); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }.padding(20)
            Divider()
            HStack(spacing: 0) {
                VStack {
                    TextField("Find a tag", text: $search).textFieldStyle(.roundedBorder).padding(12)
                    List(selection: $selected) {
                        ForEach(model.availableTags.filter { search.isEmpty || $0.localizedCaseInsensitiveContains(search) }, id: \.self) { tag in
                            HStack { Text(tag); Spacer(); Text("\(model.tagCount(tag))").foregroundStyle(.secondary) }.tag(tag)
                        }
                    }
                }.frame(width: 230)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let selected {
                            Text(selected).font(.title3.bold())
                            Text("Used on \(model.tagCount(selected)) screenshots. Changes update the whole library and future suggestions.").font(.callout).foregroundStyle(.secondary)
                            TextField("New name", text: $name).textFieldStyle(.roundedBorder)
                            Button("Rename Tag") { model.renameTag(selected, to: name) }
                                .disabled(!validName || name == selected)
                            Divider()
                            Text("Merge into an existing tag").font(.headline)
                            Picker("Destination", selection: $destination) {
                                Text("Choose a tag…").tag("")
                                ForEach(model.availableTags.filter { ContentTags.key($0) != ContentTags.key(selected) }, id: \.self) { Text($0).tag($0) }
                            }
                            Text(destination.isEmpty ? "A merged screenshot keeps only one copy of the destination tag." : "Replace “\(selected)” with “\(destination)” on \(model.tagCount(selected)) screenshots.")
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Merge Tags") { model.renameTag(selected, to: destination) }.disabled(destination.isEmpty)
                            Divider()
                            Text("Hide from automatic suggestions").font(.headline)
                            Text("Removes this tag from automatically tagged screenshots and prevents it returning. Tags you edited manually stay intact.").font(.caption).foregroundStyle(.secondary)
                            Button("Hide Automatic Tag") { model.hideTag(selected) }
                        } else { Text("Select a tag to rename, merge, or hide its automatic suggestions.").foregroundStyle(.secondary) }
                        if !model.hiddenTags.isEmpty {
                            Divider()
                            DisclosureGroup("Hidden automatic tags (\(model.hiddenTags.count))") {
                                ForEach(model.hiddenTags, id: \.self) { tag in
                                    HStack { Text(tag); Spacer(); Button("Allow Again") { model.restoreTag(tag) } }.padding(.vertical, 4)
                                }
                            }
                        }
                    }.padding(22)
                }
            }
            if model.tagManagementBusy { ProgressView("Updating tags…").padding(10) }
        }.frame(width: 720, height: 540)
        .disabled(model.tagManagementBusy)
        .alert("Tags Could Not Be Updated", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .onAppear { selected = model.availableTags.first }
        .onChange(of: selected) { _, value in name = value ?? ""; destination = "" }
        .onChange(of: model.availableTags) { _, tags in
            if let selected, !tags.contains(selected) { self.selected = tags.first }
        }
    }
    var validName: Bool {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return !value.isEmpty && value.count <= 60 && !value.contains(",")
    }
}
