import Foundation
import GatherCore

extension LibraryChecks {
    public func testBackgroundPreferencesCompatibility() async throws {
        // Existing libraries predate the intake pause field. Preserve their prior behavior.
        let legacy = Data(#"{"watchedPaths":["/fixture"],"indexingEnabled":false,"dismissedGroups":["reviewed"]}"#.utf8)
        var settings = try JSONDecoder().decode(AutomationSettings.self, from: legacy)
        try checkTrue(settings.intakeEnabled)
        try checkFalse(settings.indexingEnabled)
        try checkEqual(settings.watchedPaths, ["/fixture"])
        try checkEqual(settings.dismissedGroups, ["reviewed"])
        settings.intakeEnabled = false
        let root = try temporary(), db = root.appendingPathComponent("background.sqlite")
        let store = try LibraryStore(url: db); try await store.saveSettings(settings)
        let reopened = try LibraryStore(url: db)
        let saved = try unwrap(try await reopened.settings())
        try checkFalse(saved.intakeEnabled); try checkFalse(saved.indexingEnabled)
        try checkEqual(saved.watchedPaths, ["/fixture"]); try checkEqual(saved.dismissedGroups, ["reviewed"])
        var resumed = saved; resumed.intakeEnabled = true; try await reopened.saveSettings(resumed)
        try checkEqual(try await store.settings()?.intakeEnabled, true)
    }
}
