import SwiftUI
import AppKit

@main struct GatherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let session = AppSession.shared
    private var model: AppModel? { session.model }
    var body: some Scene {
        Window("Gather", id: "library") {
            GatherLibraryScene(session: session)
        }
        .defaultSize(width: 1380, height: 850)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Gather") { session.openLibrary?() }.keyboardShortcut("0", modifiers: .command)
                Divider()
                Button("Import Images…") { model?.chooseFiles() }.keyboardShortcut("i", modifiers: .command).disabled((model?.busy ?? true) || (model?.cleanupBusy ?? true))
                Button("Scan Folder…") { model?.chooseFolder() }.keyboardShortcut("i", modifiers: [.command, .shift]).disabled((model?.busy ?? true) || (model?.cleanupBusy ?? true))
                Divider()
                Button("Organize Desktop…") { model?.openOrganizer() }.disabled(model?.cleanupBusy ?? true)
                Button("File Operations…") { model?.showCleanupHistory = true }
                Divider()
                Button("New Collection…") { model?.newCollection = true }.keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .textEditing) {
                Button("Copy Screenshot Text") {
                    if let model, let item = model.selected { model.copyText(item) }
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled((model?.batchMode ?? true) || (model?.selected?.extractedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true))
                Button("Find Screenshots") { model?.searchFocusRequest += 1 }.keyboardShortcut("f", modifiers: .command)
            }
            CommandGroup(after: .pasteboard) {
                Button("Delete Screenshot…", role: .destructive) {
                    guard let model else { return }
                    model.requestDeletion(model.batchMode ? model.visibleBatchIDs : Set([model.selectedID].compactMap { $0 }))
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(!(model?.canDelete ?? false) || (model?.batchMode == true ? model?.visibleBatchIDs.isEmpty ?? true : model?.selected == nil))
            }
            CommandGroup(after: .toolbar) {
                Button("Open Screenshot") { if let model, let item = model.selected { model.openImage(item) } }.disabled(model?.selected == nil)
            }
        }
        MenuBarExtra("Gather", systemImage: "square.stack.3d.up.fill") {
            GatherMenuView(model: model, startupError: session.startupError)
        }.menuBarExtraStyle(.menu)
        Settings {
            if let model { AutomationSettingsView(model: model, loginItem: session.loginItem) }
        }
    }
}

struct GatherLibraryScene: View {
    let session: AppSession
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Group {
            if let model = session.model {
                LibraryView(model: model)
                    .frame(minWidth: 1000, minHeight: 640)
                    .tint(GatherTheme.accent)
            } else {
                ContentUnavailableView("Library Could Not Open", systemImage: "externaldrive.badge.exclamationmark", description: Text(session.startupError ?? "Unknown error"))
                    .frame(width: 600, height: 300)
            }
        }
        .onAppear {
            session.openLibrary = {
                openWindow(id: "library")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        }
    }
}
