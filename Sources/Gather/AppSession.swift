import AppKit

/// The library lifetime belongs to the process, independently of its windows.
@MainActor final class AppSession {
    static let shared = AppSession()
    let model: AppModel?
    let startupError: String?
    let loginItem = LoginItemController()
    var openLibrary: (() -> Void)?
    private init() {
        do { model = try AppModel(); startupError = nil }
        catch { model = nil; startupError = error.localizedDescription }
    }
}
