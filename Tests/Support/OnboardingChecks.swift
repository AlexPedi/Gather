import Foundation
import CSQLite
import GatherCore

extension LibraryChecks {
    public func testOnboardingProgressAndExistingLibraries() async throws {
        let root = try temporary(), url = root.appendingPathComponent("setup.sqlite")
        let store = try LibraryStore(url: url)
        try checkTrue(try await store.needsOnboarding())
        try checkTrue(OnboardingState().launchAtLogin)
        try checkTrue(OnboardingState().intakeEnabled)
        try checkTrue(OnboardingState().indexingEnabled)
        let legacy = try JSONDecoder().decode(OnboardingState.self, from: Data("{\"completed\":false,\"step\":1}".utf8))
        try checkTrue(legacy.launchAtLogin)
        var draft = OnboardingState(); draft.step = 1; draft.indexingEnabled = false; draft.launchAtLogin = false
        try await store.saveOnboarding(draft)
        let reopened = try LibraryStore(url: url)
        try checkEqual(try await reopened.onboarding()?.step, 1)
        try checkEqual(try await reopened.onboarding()?.launchAtLogin, false)
        try checkEqual(try await reopened.onboarding()?.indexingEnabled, false)
        try checkTrue(try await reopened.needsOnboarding())
        var manual = AutomationSettings(); manual.intakeEnabled = false; manual.indexingEnabled = false
        try await reopened.finishOnboarding(draft, settings: manual)
        try checkFalse(try await store.needsOnboarding())
        try checkEqual(try await store.settings()?.intakeEnabled, false)
        try checkEqual(try await store.settings()?.watchedPaths, [])
        // Existing libraries are not forced through setup or given new defaults.
        let existing = try LibraryStore(url: root.appendingPathComponent("existing.sqlite"))
        let item = Screenshot(path: root.appendingPathComponent("existing.png").path, sourceFolder: root.path, captureDate: Date(), fileSize: 10, width: 10, height: 10, contentHash: "fixture")
        try await existing.insert(item); try await existing.saveSettings(manual)
        try checkFalse(try await existing.needsOnboarding())
        try checkEqual(try await existing.settings()?.indexingEnabled, false)
        try checkEqual(try await existing.record(item.id), item)
    }
    public func testOnboardingAccessAndAtomicCompletion() async throws {
        let root = try temporary(), url = root.appendingPathComponent("setup.sqlite")
        let store = try LibraryStore(url: url)
        var state = OnboardingState(); state.step = 2; state.folderPath = root.path
        try await store.saveOnboarding(state)
        var baseline = AutomationSettings(); baseline.intakeEnabled = false; try await store.saveSettings(baseline)
        var settings = baseline; settings.intakeEnabled = true; settings.watchedPaths = [root.path]
        var rejected = false
        do { try await store.finishOnboarding(state, settings: settings) } catch { rejected = true }
        try checkTrue(rejected); try checkTrue(try await store.needsOnboarding())
        try checkEqual(try await store.settings()?.intakeEnabled, false)
        let access = FileAccess()
        try await store.save(try await access.grant(root, isFolder: true))
        // Inject failure after automation writes: completion and defaults must roll back together.
        var db: OpaquePointer?
        try checkEqual(sqlite3_open(url.path, &db), SQLITE_OK); defer { sqlite3_close(db) }
        try checkEqual(sqlite3_exec(db, "CREATE TRIGGER reject_setup BEFORE INSERT ON preferences WHEN NEW.key='onboarding' BEGIN SELECT RAISE(ABORT, 'setup failure fixture'); END;", nil, nil, nil), SQLITE_OK)
        var failed = false
        do { try await store.finishOnboarding(state, settings: settings) } catch { failed = true }
        try checkTrue(failed); try checkTrue(try await store.needsOnboarding())
        try checkEqual(try await store.settings()?.intakeEnabled, false)
        try checkEqual(try await store.settings()?.watchedPaths, [])
        try checkEqual(sqlite3_exec(db, "DROP TRIGGER reject_setup", nil, nil, nil), SQLITE_OK)
        try await store.finishOnboarding(state, settings: settings)
        try checkFalse(try await store.needsOnboarding())
        let reopened = try LibraryStore(url: url)
        try checkEqual(try await reopened.onboarding()?.folderPath, root.path)
        try checkEqual(try await reopened.settings()?.watchedPaths, [root.path])
        try checkEqual(try await reopened.settings()?.intakeEnabled, true)
        await access.releaseAll()
    }
}
