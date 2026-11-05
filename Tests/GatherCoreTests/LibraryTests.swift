import XCTest
import GatherTestSupport

final class LibraryTests: XCTestCase, @unchecked Sendable {
    @MainActor func testReimportAndPersistence() async throws {
        let checks = LibraryChecks(); defer { checks.clean() }
        try await checks.testReimportPreservesIdentityAndManualEditsAcrossRelaunch()
    }
    @MainActor func testDuplicates() async throws {
        let checks = LibraryChecks(); defer { checks.clean() }
        try await checks.testIdenticalContentAtDifferentPathsRemainsReviewable()
    }
    @MainActor func testIndividualFailureAndThumbnails() async throws {
        let checks = LibraryChecks(); defer { checks.clean() }
        try await checks.testCorruptFileDoesNotStopImportAndThumbnailIsBounded()
    }
    @MainActor func testAutomationRules() throws {
        let checks = LibraryChecks(); defer { checks.clean() }; try checks.testClassificationAndGrouping()
    }
    @MainActor func testProcessingPersistence() async throws {
        let checks = LibraryChecks(); defer { checks.clean() }; try await checks.testOCRMergeSearchAndRestart()
    }
    @MainActor func testWatching() async throws {
        let checks = LibraryChecks(); defer { checks.clean() }; try await checks.testWatchingStabilityAndReconciliation()
    }
    @MainActor func testVision() async throws {
        let checks = LibraryChecks(); defer { checks.clean() }; try await checks.testVisionOCR()
    }
    @MainActor func testMigration() async throws {
        let checks = LibraryChecks(); defer { checks.clean() }; try await checks.testLegacyMigration()
    }
    @MainActor func testDynamicTags() async throws {
        let checks = LibraryChecks(); defer { checks.clean() }; try await checks.testDynamicAndCustomTags()
    }
    @MainActor func testTagManagement() async throws {
        let checks = LibraryChecks(); defer { checks.clean() }; try await checks.testTagQualityAndManagement()
    }
    @MainActor func testGroupReview() async throws {
        let checks = LibraryChecks(); defer { checks.clean() }; try await checks.testGroupReviewSelectionAndMemory()
    }
    @MainActor func testGroupReviewRollback() async throws {
        let checks = LibraryChecks(); defer { checks.clean() }; try await checks.testGroupReviewValidationAndRollback()
    }
    @MainActor func testCleanupMoveAndUndo() async throws {
        let checks = LibraryChecks(); defer { checks.clean() }; try await checks.testCleanupMoveAndUndo()
    }
    @MainActor func testCleanupRecovery() async throws {
        let checks = LibraryChecks(); defer { checks.clean() }; try await checks.testCleanupPartialFailureAndRecovery()
    }
    @MainActor func testCleanupDatabaseFailure() async throws {
        let checks = LibraryChecks(); defer { checks.clean() }; try await checks.testCleanupDatabaseFailureAndOwnedRecovery()
    }
    @MainActor func testScreenshotRemoval() async throws {
        let checks = LibraryChecks(); defer { checks.clean() }; try await checks.testScreenshotRemoval()
    }
    @MainActor func testBatchActions() async throws {
        let checks = LibraryChecks(); defer { checks.clean() }; try await checks.testBatchActionsAndRollback()
    }
    @MainActor func testBackgroundPreferences() async throws {
        let checks = LibraryChecks(); defer { checks.clean() }; try await checks.testBackgroundPreferencesCompatibility()
    }
    @MainActor func testOnboardingProgress() async throws {
        let checks = LibraryChecks(); defer { checks.clean() }; try await checks.testOnboardingProgressAndExistingLibraries()
    }
    @MainActor func testOnboardingCompletion() async throws {
        let checks = LibraryChecks(); defer { checks.clean() }; try await checks.testOnboardingAccessAndAtomicCompletion()
    }
    @MainActor func testOutgoingDrag() async throws {
        let checks = LibraryChecks(); defer { checks.clean() }; try await checks.testOutgoingDragCopiesAndRepresentations()
    }
}
