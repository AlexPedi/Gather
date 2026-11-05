import AppKit

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel? { AppSession.shared.model }
    private var terminating = false
    private var startupTask: Task<Void, Never>?
    func applicationDidFinishLaunching(_ notification: Notification) {
        startupTask = Task { await model?.load() }
        AppSession.shared.loginItem.refresh()
    }
    func applicationDidBecomeActive(_ notification: Notification) { AppSession.shared.loginItem.refresh() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppSession.shared.openLibrary?()
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        guard !terminating else { return .terminateLater }
        terminating = true
        Task {
            await startupTask?.value
            await AppSession.shared.loginItem.finish()
            await model.finishPendingEdits()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
