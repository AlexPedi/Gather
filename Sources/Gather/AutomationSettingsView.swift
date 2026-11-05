import SwiftUI
import GatherCore

struct AutomationSettingsView: View {
    @Bindable var model: AppModel
    @Bindable var loginItem: LoginItemController
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            Label("Gather", systemImage: "square.stack.3d.up.fill").font(.title.bold())
            Text("Gather keeps importing screenshots when its window is closed. Use the menu bar to reopen it, pause intake, or quit. Text recognition and organization run entirely on this Mac.").foregroundStyle(.secondary)
            Button("Review Guided Setup…") { AppSession.shared.openLibrary?(); model.reviewSetup() }.disabled(model.loading || model.onboardingBusy)
            Divider()
            Toggle("Launch Gather at login", isOn: Binding(get: { loginItem.registered }, set: { loginItem.setEnabled($0) }))
                .disabled(loginItem.busy || loginItem.developmentBuild)
            Text(loginItem.message).font(.caption).foregroundStyle(.secondary)
            if loginItem.busy { ProgressView().controlSize(.small) }
            if let error = loginItem.error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            if !loginItem.developmentBuild { Button("Open Login Items Settings…", action: loginItem.openSettings) }
            Divider()
            Toggle("Automatically import new screenshots", isOn: Binding(get: { model.automation.intakeEnabled }, set: { model.setIntakeEnabled($0) }))
            Text("Pausing intake lets an in-progress scan finish. Missed screenshots are picked up after you resume.").font(.caption).foregroundStyle(.secondary)
            HStack { Text("Watched folders").font(.headline); Spacer(); Button("Add Folder…", action: model.chooseWatchFolder) }
            if model.automation.watchedPaths.isEmpty {
                Text("Choose your Desktop or screenshot destination folder to enable automatic intake.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(model.automation.watchedPaths, id: \.self) { path in
                HStack {
                    Label(path, systemImage: "folder").font(.caption).lineLimit(2).textSelection(.enabled)
                    Spacer()
                    Button("Stop") { model.stopWatching(path) }.accessibilityLabel("Stop watching \(path)")
                }
            }
            Text(model.watchStatus).font(.caption).foregroundStyle(.secondary)
            Divider()
            Toggle("Automatically read text, title and categorize screenshots", isOn: $model.automation.indexingEnabled)
                .onChange(of: model.automation.indexingEnabled) { _, _ in model.saveAutomation() }
            Text("Uses Apple Vision OCR and text-based rules. Images without enough text remain Uncategorized. Your edits are preserved. Pausing lets the current image finish.").font(.caption).foregroundStyle(.secondary)
            Text(model.indexingStatus).font(.caption)
            if model.items.contains(where: { $0.ocrStatus == "failed" }) {
                Button("Retry Failed Screenshots") {
                    for item in model.items where item.ocrStatus == "failed" { model.retryOCR(item.id) }
                }
            }
            Divider()
            Text("Groups appear automatically in the sidebar. Related groups use shared text and capture timing; exact duplicates are grouped separately. Save a group as a collection to keep it, or dismiss it. Files never move.").font(.caption).foregroundStyle(.secondary)
            if model.reviewedGroupCount > 0 {
                Text("\(model.reviewedGroupCount) saved or dismissed suggestions remembered. Mostly overlapping groups stay hidden; substantially new groups can still appear.").font(.caption).foregroundStyle(.secondary)
                Button("Show Reviewed Groups Again") { model.resetGroupReviews() }.disabled(model.groupReviewBusy)
                    .help("Reset suggestion history, including older dismissals. Existing collections remain unchanged.")
            }
            Button("Grant File Access…", action: model.grantAgain)
        }.padding(28)
        }.frame(width: 590, height: 650)
        .onAppear { loginItem.refresh() }
    }
}
