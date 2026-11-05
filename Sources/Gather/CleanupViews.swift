import SwiftUI
import GatherCore
import AppKit

struct OrganizeDesktopView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ViewState<Set<UUID>> private var selected: Set<UUID>
    init(model: AppModel) {
        self.model = model
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.resolvingSymlinksInPath().path
        let defaults = model.visible.filter { URL(fileURLWithPath: $0.path).deletingLastPathComponent().resolvingSymlinksInPath().path == desktop }.map(\.id)
        _selected = ViewState(initialValue: model.batchMode ? model.visibleBatchIDs : model.selectedID.map { Set([$0]) } ?? Set(defaults))
    }
    private var executed: Bool { model.cleanupPreview.map { plan in model.cleanupHistory.contains { $0.id == plan.id } } ?? false }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Label("Organize Desktop", systemImage: "folder.badge.gearshape").font(.title2.bold()); Spacer(); Button(executed ? "Done" : "Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }.padding(22)
            Divider()
            if let plan = model.cleanupPreview {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(executed ? "File operation results" : "Review before moving").font(.headline)
                        Text("Destination: \(plan.destinationFolder)").font(.callout).textSelection(.enabled)
                        Text(executed ? "Each file has its own result. Successfully moved screenshots remain in Gather." : "Gather will move only the listed screenshots. Existing destination files will never be overwritten. Keep enough free space for a verified copy.").font(.callout).foregroundStyle(.secondary)
                        ForEach(plan.entries) { entry in CleanupEntryRow(entry: entry, preview: !executed) }
                    }.padding(22)
                }
                Divider()
                HStack {
                    if !executed { Button("Back") { model.cleanupPreview = nil } }
                    Spacer()
                    if model.cleanupBusy { ProgressView().controlSize(.small); Text(model.cleanupStatus).font(.caption) }
                    if executed { Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
                    else {
                        Button("Move \(plan.entries.filter { $0.phase == .pending }.count) Screenshots") { model.performCleanup() }
                            .buttonStyle(.borderedProminent).tint(GatherTheme.accent)
                            .disabled(!plan.entries.contains { $0.phase == .pending })
                    }
                }.padding(18)
            } else {
                HStack {
                    Text("Choose screenshots from the current view. You’ll review exact paths next.").font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    Button("Select All") { selected = Set(model.visible.map(\.id)) }
                    Button("Clear") { selected.removeAll() }
                }.padding(20)
                List {
                    ForEach(model.visible) { item in
                        HStack(spacing: 12) {
                            Toggle(isOn: Binding(get: { selected.contains(item.id) }, set: { value in
                                if value { selected.insert(item.id) } else { selected.remove(item.id) }
                            })) { EmptyView() }.toggleStyle(.checkbox).accessibilityLabel("Move \(item.title)")
                            ScreenshotImage(item: item, cache: model.cache).frame(width: 75, height: 55)
                            VStack(alignment: .leading, spacing: 4) { Text(item.title).font(.callout.weight(.medium)); Text(item.path).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                        }.padding(.vertical, 5)
                    }
                }
                HStack {
                    Text("\(selected.count) selected").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if model.cleanupBusy { ProgressView().controlSize(.small); Text(model.cleanupStatus).font(.caption) }
                    Button("Choose Destination…") { model.chooseCleanupDestination(ids: selected) }.buttonStyle(.borderedProminent).tint(GatherTheme.accent).disabled(selected.isEmpty)
                }.padding(18)
            }
        }.frame(minWidth: 720, idealWidth: 880, minHeight: 540, idealHeight: 700)
            .disabled(model.cleanupBusy).interactiveDismissDisabled(model.cleanupBusy)
            .alert("File Operation Needs Attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK") { model.error = nil }
            } message: { Text(model.error ?? "") }
    }
}
struct CleanupEntryRow: View {
    let entry: CleanupEntry
    var preview = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text(entry.title).font(.headline); Spacer(); Text(preview && entry.phase == .pending ? "Ready" : entry.status).font(.caption).foregroundStyle(entry.phase == .complete ? Color.green : .secondary) }
            Text("From: \(entry.from)\nTo: \(entry.to)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            if preview, URL(fileURLWithPath: entry.originalPath).lastPathComponent != URL(fileURLWithPath: entry.destinationPath).lastPathComponent {
                Label("Filename adjusted to avoid a collision", systemImage: "doc.badge.plus").font(.caption).foregroundStyle(GatherTheme.accent)
            }
            if let detail = entry.detail { Text(detail).font(.caption).foregroundStyle(entry.phase == .complete ? Color.secondary : .orange).textSelection(.enabled) }
            if entry.phase == .needsAttention {
                Text("Recovery paths:\n\(entry.stagingPath)\n\(entry.holdingPath)").font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
            }
            if !preview {
                HStack {
                    Button("Reveal Source") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.from)]) }
                    Button("Reveal Destination") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: entry.to)]) }
                }.font(.caption)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
    }
}
struct CleanupHistoryView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ViewState<CleanupOperation?> private var undoDraft: CleanupOperation?
    var body: some View {
        VStack(spacing: 0) {
            HStack { Label("File Operations", systemImage: "clock.arrow.circlepath").font(.title2.bold()); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction) }.padding(22)
            Divider()
            if model.cleanupHistory.isEmpty { ContentUnavailableView("No file operations yet", systemImage: "folder", description: Text("Moves and undo results will appear here.")) }
            else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(model.cleanupHistory) { operation in
                            DisclosureGroup {
                                ForEach(operation.entries) { CleanupEntryRow(entry: $0) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(operation.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.headline)
                                        Text("\(operation.entries.count) files · \(operation.destinationFolder)").font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    Spacer()
                                    if operation.canUndo { Button("Preview Undo…") { undoDraft = operation } }
                                }.padding(.vertical, 8)
                            }
                        }
                    }.padding(22)
                }
            }
            Divider()
            HStack {
                Button("Grant Access…", action: model.grantAgain)
                Button("Check Interrupted Operations") { model.recoverCleanup() }
                Spacer()
                if model.cleanupBusy { ProgressView().controlSize(.small); Text(model.cleanupStatus).font(.caption) }
            }.padding(18)
        }.frame(minWidth: 760, idealWidth: 900, minHeight: 520, idealHeight: 680)
        .disabled(model.cleanupBusy).interactiveDismissDisabled(model.cleanupBusy)
        .sheet(item: $undoDraft) { operation in UndoCleanupView(model: model, operation: operation) }
        .alert("File Operation Needs Attention", isPresented: Binding(get: { model.error != nil && undoDraft == nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}
struct UndoCleanupView: View {
    @Bindable var model: AppModel
    let operation: CleanupOperation
    @Environment(\.dismiss) private var dismiss
    @ViewState<Bool> private var started = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Review Undo").font(.title2.bold())
            Text("Restore the files below to their original locations. If a source name is occupied or a moved file has changed, that file will remain in place and its failure will be reported.").foregroundStyle(.secondary)
            ScrollView {
                ForEach(operation.entries.filter(\.canUndo)) { entry in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.title).font(.headline)
                        Text("From: \(entry.destinationPath)\nTo: \(entry.originalPath)").font(.caption).textSelection(.enabled)
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if model.cleanupBusy { ProgressView().controlSize(.small) }
                Button("Undo \(operation.entries.filter(\.canUndo).count) Moves") { started = true; model.undoCleanup(operation.id) }.buttonStyle(.borderedProminent).tint(GatherTheme.accent)
            }
        }.padding(24).frame(width: 640, height: 460).disabled(model.cleanupBusy).interactiveDismissDisabled(model.cleanupBusy)
            .onChange(of: model.cleanupBusy) { _, busy in if started && !busy && model.error == nil { dismiss() } }
            .alert("Undo Could Not Finish", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK") { model.error = nil }
            } message: { Text(model.error ?? "") }
    }
}
