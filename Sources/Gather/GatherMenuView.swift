import SwiftUI
import AppKit

struct GatherMenuView: View {
    let model: AppModel?
    let startupError: String?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        Button("Open Gather") { openWindow(id: "library"); NSApplication.shared.activate(ignoringOtherApps: true) }
            .keyboardShortcut("o", modifiers: .command)
        if let model {
            Text("\(model.items.count) screenshots · \(model.pendingCount) pending")
            Text(model.watchStatus.isEmpty ? "Starting automatic intake…" : model.watchStatus)
            if model.cleanupBusy { Text(model.cleanupStatus) }
            if model.error != nil { Text("Needs attention — open Gather for details") }
            Divider()
            Toggle("Automatic Screenshot Intake", isOn: Binding(get: { model.automation.intakeEnabled }, set: { model.setIntakeEnabled($0) }))
                .disabled(model.loading || !model.onboarding.completed)
            Toggle("Automatic Organization", isOn: Binding(get: { model.automation.indexingEnabled }, set: { model.automation.indexingEnabled = $0; model.saveAutomation() }))
                .disabled(model.loading || !model.onboarding.completed)
        } else { Text(startupError ?? "Library unavailable") }
        Divider()
        Button("Settings…") { openSettings(); NSApplication.shared.activate(ignoringOtherApps: true) }.keyboardShortcut(",", modifiers: .command)
        Divider()
        Button("Quit Gather") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q", modifiers: .command)
    }
}
