import GatherTestSupport
import Foundation
@main struct CheckRunner {
    @MainActor static func main() async throws {
        if CommandLine.arguments.contains("--benchmark") { try await Benchmark.run(); return }
        let tests = LibraryChecks()
        defer { tests.clean() }
        if let index = CommandLine.arguments.firstIndex(of: "--seed-group-library"), CommandLine.arguments.count > index + 1 {
            try await tests.seedGroupReviewLibrary(at: URL(fileURLWithPath: CommandLine.arguments[index + 1])); return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--seed-tag-library"), CommandLine.arguments.count > index + 1 {
            try await tests.seedTagManagementLibrary(at: URL(fileURLWithPath: CommandLine.arguments[index + 1])); return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--audit-tags"), CommandLine.arguments.count > index + 1 {
            print(try tests.auditTags(at: URL(fileURLWithPath: CommandLine.arguments[index + 1]))); return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--make-watch-fixture"), CommandLine.arguments.count > index + 1 {
            try tests.createOCRFixture(at: URL(fileURLWithPath: CommandLine.arguments[index + 1]), extraLine: CommandLine.arguments.count > index + 2 ? CommandLine.arguments[index + 2] : nil); print("Created synthetic OCR fixture"); return
        }
        try await tests.testReimportPreservesIdentityAndManualEditsAcrossRelaunch()
        print("PASS: reimport, identity, edits, collections, persistence, unchanged originals")
        try await tests.testIdenticalContentAtDifferentPathsRemainsReviewable()
        print("PASS: exact duplicate hashes with distinct original records")
        try await tests.testCorruptFileDoesNotStopImportAndThumbnailIsBounded()
        print("PASS: individual failures, screenshot heuristics, bounded thumbnails")
        try tests.testClassificationAndGrouping()
        print("PASS: conservative classification, related groups and exact duplicates")
        try await tests.testOCRMergeSearchAndRestart()
        print("PASS: OCR merge, manual edits, FTS indexing, restart and persisted settings")
        try await tests.testWatchingStabilityAndReconciliation()
        print("PASS: stable-file intake, repeated polls and launch reconciliation")
        try await tests.testVisionOCR()
        print("PASS: actual Vision OCR, category, full-text search and isolated processing failure")
        try await tests.testLegacyMigration()
        print("PASS: existing version-1 library migration preserves metadata and queues OCR")
        try await tests.testDynamicAndCustomTags()
        print("PASS: open-vocabulary content tags, existing-image retagging, custom tag catalog and manual preservation")
        try await tests.testTagQualityAndManagement()
        print("PASS: tag quality, singular variants, rename/merge, future aliases, stale edits, hidden suggestions and persistence")
        try await tests.testGroupReviewSelectionAndMemory()
        print("PASS: group evidence, curated collection save, excluded originals, FTS and persistent overlapping-group decisions")
        try await tests.testGroupReviewValidationAndRollback()
        print("PASS: invalid group selections rejected and injected save failure rolls back collection, memberships, search and history")
        try await tests.testCleanupMoveAndUndo()
        print("PASS: verified moves, collision naming, metadata, blocked undo and retry")
        try await tests.testCleanupPartialFailureAndRecovery()
        print("PASS: per-file failure, importer reservations and interrupted move recovery")
        try await tests.testCleanupDatabaseFailureAndOwnedRecovery()
        print("PASS: database failure retains originals and recovery never removes foreign destination files")
        try await tests.testScreenshotRemoval()
        print("PASS: screenshot removal, atomic validation, search cleanup, unchanged originals and persistent intake suppression")
        try await tests.testBatchActionsAndRollback()
        print("PASS: batch favorites, tag aliases, collection deduplication, field preservation, validation and atomic rollback")
        try await tests.testBackgroundPreferencesCompatibility()
        print("PASS: legacy automation preferences preserve intake behavior and pause/resume persists independently of OCR")
        try await tests.testOnboardingProgressAndExistingLibraries()
        print("PASS: onboarding resume, manual completion, persistence and existing-library defaults")
        try await tests.testOnboardingAccessAndAtomicCompletion()
        print("PASS: onboarding requires folder grants and atomically commits completion with automation defaults")
        try await tests.testOutgoingDragCopiesAndRepresentations()
        print("PASS: outgoing drag file/image representations, exact bytes and filenames, independent copies, stale/missing originals")
        print("All 21 integration checks passed.")
    }
}
