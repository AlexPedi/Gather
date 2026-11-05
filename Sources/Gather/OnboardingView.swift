import SwiftUI
import GatherCore

struct OnboardingView: View {
    @Bindable var model: AppModel
    @Bindable var loginItem: LoginItemController
    private var step: Int { model.onboarding.step }
    private func advance() { model.onboarding.step = min(2, step + 1); model.saveSetupProgress() }
    private var primaryTitle: String {
        if step == 0 { return "Set Up Gather" }
        if step == 1 { return model.setupFolderReady ? "Use This Folder" : "Choose Screenshot Folder…" }
        return model.setupFolderReady && model.onboarding.intakeEnabled ? "Start Gathering" : "Open My Library"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Gather", systemImage: "square.stack.3d.up.fill").font(.headline).foregroundStyle(GatherTheme.accent)
                Spacer()
                Text("Step \(step + 1) of 3").font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.75))
            }.padding(.bottom, 22)
            HStack(spacing: 6) {
                ForEach(0..<3) { index in Capsule().fill(index <= step ? GatherTheme.accent : Color.secondary.opacity(0.15)).frame(height: 3) }
            }.padding(.bottom, 26).accessibilityLabel("Setup step \(step + 1) of 3")
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if step == 0 { welcome }
                    else if step == 1 { folder }
                    else { defaults }
                    if let error = model.onboardingError {
                        Label(error, systemImage: "exclamationmark.triangle").font(.system(size: 15)).foregroundStyle(.orange).textSelection(.enabled)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider().padding(.vertical, 18)
            HStack {
                if step > 0 {
                    Button("Back") { model.onboarding.step -= 1; model.saveSetupProgress() }.disabled(loginItem.busy)
                } else {
                    Button("Import Manually Instead") { model.finishSetup(manual: true) }.buttonStyle(.link)
                        .help("Skip folder access. You can set up automatic intake later in Settings.")
                }
                Spacer()
                if model.onboardingBusy || loginItem.busy { ProgressView().controlSize(.small) }
                if step == 1 {
                    Button("Skip for Now") {
                        model.onboarding.folderPath = nil; model.onboarding.intakeEnabled = false
                        advance()
                    }.buttonStyle(.link)
                }
                Button {
                    if step == 1 && !model.setupFolderReady { model.chooseSetupFolder() }
                    else if step == 2 {
                        Task {
                            if !loginItem.developmentBuild && model.onboarding.launchAtLogin != loginItem.registered {
                                loginItem.setEnabled(model.onboarding.launchAtLogin)
                                await loginItem.finish()
                                guard loginItem.error == nil else { return }
                                if loginItem.status == .requiresApproval { return }
                            }
                            model.finishSetup()
                        }
                    }
                    else { advance() }
                } label: {
                    HStack(spacing: 10) {
                        Text(primaryTitle)
                        Image(systemName: step == 1 && !model.setupFolderReady ? "folder.badge.plus" : "arrow.right")
                    }.font(.system(size: 14, weight: .semibold)).padding(.horizontal, 10).frame(minHeight: 30)
                }.buttonStyle(.borderedProminent).controlSize(.large).tint(GatherTheme.accent).keyboardShortcut(.defaultAction)
                    .disabled(loginItem.busy)
            }
        }.font(.system(size: 15)).lineSpacing(3).padding(30).frame(width: 640, height: 710)
            .disabled(model.onboardingBusy)
            .interactiveDismissDisabled(model.onboardingBusy || loginItem.busy || !model.onboarding.completed)
            .onAppear { loginItem.refresh() }
    }
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            Image(systemName: "photo.stack").font(.system(size: 42)).foregroundStyle(GatherTheme.accent).padding(.top, 4)
            Text("Save the screenshot. Find the idea.").font(.system(size: 28, weight: .semibold))
            Text("Gather brings your screenshots together, organizes the details, and helps you find what you saved.").foregroundStyle(Color.primary.opacity(0.75))
            explanation("Bring your screenshots together", detail: "Connect the folder you already use. You choose what Gather can read, and we’ll explain why before asking for access.", icon: "folder")
            explanation("Find what you saved", detail: "Remember the topic, not the filename. Search screenshot text and explore suggested titles, tags, and related groups—all on this Mac.", icon: "sparkles")
            explanation("Your originals stay put", detail: "Automatic intake doesn’t move or delete files. Moving files is a separate action with a preview.", icon: "checkmark.shield")
        }
    }
    private var folder: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Start with the folder you already use.").font(.system(size: 26, weight: .semibold))
            Text("Keep taking screenshots the way you always have. Choose where they’re saved—usually Desktop—and Gather will bring them into your library.").foregroundStyle(Color.primary.opacity(0.75))
            explanation("Why Gather needs folder access", detail: "To read screenshot images in this folder, import existing captures, and notice new ones while Gather runs. It checks this folder, not your whole Mac.", icon: "folder.badge.questionmark")
            Text("Choose Screenshot Folder opens the macOS folder picker. Select your folder and click Allow Folder. macOS may also ask to allow access to Desktop or Documents.").font(.system(size: 15)).foregroundStyle(Color.primary.opacity(0.75))
            if let path = model.onboarding.folderPath {
                VStack(alignment: .leading, spacing: 10) {
                    Label(model.setupFolderReady ? "Folder connected" : "Folder access needs attention", systemImage: model.setupFolderReady ? "checkmark.circle.fill" : "exclamationmark.triangle")
                        .foregroundStyle(model.setupFolderReady ? Color.green : .orange)
                    Text(path).font(.system(size: 14)).textSelection(.enabled)
                }.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9))
            }
            if model.setupFolderReady {
                Button("Change Folder…", action: model.chooseSetupFolder).buttonStyle(.link)
            }
            Text("Prefer to import images yourself? Choose Skip for Now. You can connect a folder from Settings whenever you’re ready.").font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.75))
        }
    }
    private var defaults: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("A little order, your way.").font(.system(size: 26, weight: .semibold))
            Text("Let Gather take care of the details. Choose what happens automatically; you can change these defaults in Settings.").foregroundStyle(Color.primary.opacity(0.75))
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Automatically import screenshots", isOn: $model.onboarding.intakeEnabled)
                    .disabled(!model.setupFolderReady).onChange(of: model.onboarding.intakeEnabled) { _, _ in model.saveSetupProgress() }
                Text(model.setupFolderReady ? "Keep taking screenshots. New and existing captures flow into your library from your chosen folder, even when the library window is closed." : "Connect a screenshot folder later to enable automatic intake. You can still import images manually.").font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.75))
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Read text and suggest organization", isOn: $model.onboarding.indexingEnabled)
                    .onChange(of: model.onboarding.indexingEnabled) { _, _ in model.saveSetupProgress() }
                Text("Find it for the reason you saved it. Gather recognizes text for search and suggests titles, tags, and related groups. Processing stays on this Mac. No additional permission is needed.").font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.75))
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Launch Gather at login", isOn: $model.onboarding.launchAtLogin)
                    .disabled(loginItem.busy || loginItem.developmentBuild)
                    .onChange(of: model.onboarding.launchAtLogin) { _, _ in model.saveSetupProgress() }
                Text("Keep Gather ready after you restart your Mac. When you finish setup, macOS will register Gather to open when you sign in. You may need to approve it in Login Items.").font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.75))
                Text(loginItem.developmentBuild ? loginItem.message : model.onboarding.launchAtLogin != loginItem.registered ? "Your choice will be applied when you finish setup." : loginItem.message).font(.system(size: 14)).foregroundStyle(Color.primary.opacity(0.75))
                if loginItem.status == .requiresApproval { Button("Open Login Items Settings…", action: loginItem.openSettings) }
                if let error = loginItem.error { Text(error).font(.system(size: 14)).foregroundStyle(.orange) }
            }
        }.toggleStyle(.checkbox).controlSize(.large).tint(GatherTheme.accent)
    }
    private func explanation(_ title: String, detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundStyle(GatherTheme.accent).frame(width: 25).font(.title3)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(detail).font(.system(size: 15)).foregroundStyle(Color.primary.opacity(0.75)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
