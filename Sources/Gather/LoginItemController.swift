import Foundation
import Observation
import ServiceManagement

@MainActor @Observable final class LoginItemController {
    private(set) var status = SMAppService.mainApp.status
    private(set) var busy = false
    var error: String?
    private var task: Task<Void, Never>?
    var registered: Bool { status == .enabled || status == .requiresApproval }
    var developmentBuild: Bool { Bundle.main.object(forInfoDictionaryKey: "GatherDevelopmentDataDirectory") != nil }
    var message: String {
        if developmentBuild { return "Launch at login is unavailable in isolated test builds." }
        switch status {
        case .enabled: return "Gather is enabled to open at login."
        case .requiresApproval: return "Approval required in System Settings → General → Login Items."
        case .notRegistered: return "Gather will not open automatically at login."
        case .notFound: return "macOS cannot find this app’s login service. Keep Gather in a stable location and try again."
        @unknown default: return "macOS reported an unknown login item status."
        }
    }
    func refresh() { status = SMAppService.mainApp.status }
    func setEnabled(_ enabled: Bool) {
        guard !busy, !developmentBuild else { return }
        busy = true; error = nil
        task = Task {
            defer { refresh(); busy = false }
            do {
                if enabled { try SMAppService.mainApp.register() }
                else { try await SMAppService.mainApp.unregister() }
            } catch { self.error = "Could not change launch at login: \(error.localizedDescription)" }
        }
    }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
    func finish() async { await task?.value }
}
