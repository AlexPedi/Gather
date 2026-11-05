# Architecture

**Gather** is a main-actor SwiftUI/AppKit app; **GatherCore** holds local services. No external package or service is required. SQLite comes from macOS through CSQLite.

## Persistence and concurrency

`LibraryStore` serializes prepared SQLite statements. Version 1 stored complete Codable metadata, unique paths, nonunique content hashes, collections and security bookmarks. Transactional migration 2 adds an indexed OCR status column, preferences and an FTS5 virtual table, bootstrapping existing metadata. Subsequent screenshot writes update the model, status column and FTS document in the same transaction. FTS documents contain title, filename, category, tags, extracted text and collection names. User input is quoted before being used as FTS terms.

`updateMetadata` merges user-owned fields into the latest record. `completeOCR` reads that latest record and preserves manual fields. Content hashes prevent a stale OCR result or failure from overwriting a newly replaced file. Changed source files reset pending processing without changing record identity or manual corrections. UI saves are serialized and flushed on normal quit; reloads avoid replacing optimistic edits made while a fetch is in flight.

## Intake

`FileAccess` persists and restores security-scoped bookmarks. `Importer` reads properties, streams SHA-256 and validates a small decode off the main actor. Reimport checks content: unchanged paths are no-ops, changed paths retain stable identity and queue fresh OCR, distinct duplicate originals remain separate records.

`FolderWatcher` polls authorized screenshot folders every three seconds. `StabilityGate` requires equal nonempty size and modification date across two polls. Each watcher marks fingerprints after attempting import, so repeated polls neither duplicate records nor spin on a corrupt unchanged file. Restart/wake reconciliation is inherent in rescanning. Stopping a folder removes its gate on the next pass. One in-flight reconciliation guard prevents overlap even across actor suspension. Polling is deliberately simple; filesystem events could later reduce scanning overhead. Folder/source errors are surfaced without logging screenshot content.

## Processing and classification

`OCRWorker` permits one in-flight image. It persists processing before recognition, uses ImageIO to bound the OCR input to 3,200 pixels, performs an accurate `VNRecognizeTextRequest`, then saves text and classifications. Failure is per-image and durable; Retry queues it again. Launch resets interrupted processing to pending. Completed unchanged content is not recognized again.

`Classifier` uses complete word/phrase evidence from OCR. Two distinct rule terms and an unambiguous winning category are required. Ties and insufficient evidence stay Uncategorized. A readable recognized line supplies a title; otherwise the date fallback remains. Auto tags come from `ContentTags`, an open vocabulary extracted with a per-call Natural Language tagger over OCR nouns and named entities, with token-frequency fallback. Tagging does not depend on winning a predefined category. Names are deduplicated case/diacritic-insensitively. A persistent custom catalog supports unused tags. Migration 3 adds a tagging-version column so existing indexed images refresh their tags without rerunning OCR; manual tags remain untouched. No language model, network inference or visual-content claim is involved.

## Grouping

Automatic category groups are dynamic filters. `Grouper` separately clusters identical hashes and related text. Related candidates need at least four shared useful tokens, Jaccard overlap of at least 0.22 and captures within 45 minutes. At most 40 preceding recognized images are compared per image. Union-find joins related candidates. Stable group IDs hash sorted member IDs and group type, so dismissals survive relaunch for the same membership set. Saving a group creates a user collection and adds memberships without changing physical files. Mostly overlapping reviewed groups stay suppressed; substantially new membership may be offered again.

## UI and cache

The three-column interface uses a lazy grid, date sections, list mode, category chips, automatic groups and an inspector. Content-derived and custom tags populate the filter row, cards and editable inspector chips. A cached tag index supplies counts. Query work is debounced for 250 ms; SQLite FTS results supplement immediate metadata filtering. The inspector exposes extracted text, Copy and Retry. Automation settings manage watched folders and pause indexing. Active folders and pending work have real status indicators.

`ThumbnailCache` serializes downsampling and caches JPEGs by content hash and requested size: 700 pixels for the grid, 1,200 for inspector, 2,200 for large preview. Cached previews can remain available when originals are missing; source readability is checked separately. There is no cache eviction policy yet.

A development-only `GatherDevelopmentDataDirectory` Info.plist value permits an isolated UI-check bundle. Production packaging does not set it. `ViewState` aliases the macOS 14 SwiftUI property wrapper because this Command Line Tools SDK also exports a State macro whose plugin is missing.

## Testing and remaining work

`GatherTestSupport` shares nineteen integration scenarios between the standalone `GatherChecks` executable and XCTest wrappers. Real Vision tests need native macOS pixel-buffer access outside restricted execution sandboxes. See VERIFICATION.md.

Optional Foundation Models, event-based watching, visual embeddings and distribution QA remain future work.

## Apple references

- [Vision text recognition](https://developer.apple.com/documentation/vision/vnrecognizetextrequest)
- [ImageIO thumbnail generation](https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex(_:_:_:))
- [Security-scoped bookmarks](https://developer.apple.com/documentation/foundation/nsurl/bookmarkcreationoptions/withsecurityscope)

## Tag quality and management (0.3)

Suggestion version 2 uses Apple's local noun lemma scheme, with conservative irregular/plural fallback, and suppresses interface chrome words before ranking. The generic fallback applies the same noise filter. Proper names retain their surface forms; custom labels are never stemmed or stripped as noise.

`TagRules` is a separate durable preference record containing canonical aliases and hidden automatic labels. Rename/merge runs catalog, screenshot payload, and FTS changes in one SQLite transaction. The internal write primitive avoids nested transactions. Aliases apply to future OCR/retag results, custom catalog writes and stale manual-edit snapshots. Alias chains support reverse and case-only renames without looping. Hidden suggestions preserve manually edited tag lists. Tagging version 2 reuses stored text for existing images and does not require a schema change or new OCR.

The Manage Tags sheet previews affected counts, supports renaming or choosing an existing merge destination, and lets users hide/restore automatic suggestions. A read-only audit tool reports aggregate tag statistics without printing screenshot text or names. Ten shared integration scenarios cover these paths in addition to the earlier library/automation tests.

Apple's lemma API reference: https://developer.apple.com/documentation/naturallanguage/nltagscheme/lemma

## Curated group review (0.4)

`AutomaticGroup` now carries its kind, duplicate-content fingerprint and actual pairwise evidence (member IDs, shared terms, Jaccard score and capture gap). The grouper excludes interface noise, records accepted edges, and indexes them by connected component rather than rescanning all edges for each group. Review explains indirect connections and shows the real capture span without claiming every member matches every other member.

`GroupReviewView` snapshots a suggestion, displays lazy thumbnail cards and large previews, and maintains a local include/exclude set and collection name. Saving passes only currently existing selected IDs. Store validation rejects empty selections, foreign IDs, missing records and invalid names. Collection creation, memberships, FTS and review history are committed atomically through the store's internal write primitive; originals and manual metadata are untouched.

`GroupReviewHistory` lives in its own preferences record. Accepted and dismissed decisions retain the original membership, kind, content fingerprint and optional collection ID. Exact-ID matches, related subsets or membership Jaccard overlap >= 0.6 with at least two shared IDs are suppressed. Duplicate groups additionally match the reviewed exact-content hash, even across new record IDs. This handles small changes without hiding unrelated new sessions. Settings resets both this history and legacy exact-ID dismissals transactionally while preserving collections. A model review revision prevents an older background reload from restoring stale suggestions, and pending review writes are awaited on normal quit.

Twelve shared integration scenarios include selected-subset saving, collection search, excluded-source preservation, durable overlap suppression, duplicate-content suppression, review-history reset and deliberate SQLite-trigger failure to prove full rollback.

## Physical organization (0.5)

Schema 4 adds cleanup_operations and cleanup_paths. CleanupService serializes operations and checkpoints every transfer phase. A preview reserves collision-free destination names; execution rechecks the current library record, original SHA-256, regular-file identity and all target paths. An exclusive hidden destination file receives bytes and file metadata. After verification, RENAME_EXCL publishes it without replacing existing files. The database changes only the latest record’s path, preserving concurrent metadata edits. The original is verified again, renamed exclusively into a journaled holding path, verified and removed. Completed entries release their import/OCR reservations.

Source and destination folders receive persisted bookmarks through explicit native selection. Importer defers reserved paths; FolderWatcher retries them rather than marking them observed. OCR discards a stale-path failure and requeues the record. Recovery restores held originals and removes only journal-identified copies, or accepts a verified completed move if the source is already gone. Ambiguous cases retain files and reservations for user review. Undo uses the same engine in reverse and rejects occupied or changed paths. The journal records current per-file outcomes; it is not an immutable audit trail.

## Batch metadata (0.6)

BatchAction defines field-level favorite, add/remove tag and collection-assignment commands. LibraryStore.applyBatch validates the complete ID set, tag and collection before writing. It reads latest records inside one SQLite transaction, applies aliases, preserves unrelated fields and writes FTS alongside payloads; a failed write rolls back records, catalog and search together.

AppModel keeps a separate batch selection from the inspector. The actionable set intersects visible IDs and is pruned when results change, preventing hidden selections. Grid cards and list checkboxes share this set. Batch actions wait for pending edits/catalog writes, disable editing during the transaction and refresh from persistence; quit waits for the batch task. Organize Desktop uses the batch selection as its initial selection when active. No new schema migration is required.

## Process and background lifetime (0.7)

AppSession owns the single AppModel for the process. AppDelegate starts loading independently of any window and explicitly refuses automatic termination after the last window closes. A single identified SwiftUI Window and MenuBarExtra share the model. The library scene saves its OpenWindowAction in AppSession so the delegate can handle Dock/Finder reopen events after closure. File → Open Gather supplies a keyboard-accessible fallback. Startup is awaited before quit flushes model and login-service tasks.

AutomationSettings now encodes intakeEnabled; its custom decoder defaults this missing field to true for existing libraries while preserving indexing and review preferences. The watch loop pauses new scans while this flag is false and reconciles the same watched paths on resume. OCR remains independently controlled. No schema migration or helper process is needed.

LoginItemController reads SMAppService.mainApp.status, refreshes on activation/settings presentation, registers only on explicit toggle, and awaits unregister. Enabled, not registered, approval-required, not-found and error states are distinct. Login registration is disabled in isolated development bundles; production packages use the actual system status. No synthetic preference claims that registration succeeded.

Apple references: [main app login service](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp), [registration](https://developer.apple.com/documentation/servicemanagement/smappservice/register()), [single SwiftUI window](https://developer.apple.com/documentation/swiftui/window), [window-close termination policy](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationshouldterminateafterlastwindowclosed(_:)).

## Guided onboarding (0.8)

OnboardingState stores step, completion, selected folder and pending intake/indexing preferences in the existing preferences table. LibraryStore.needsOnboarding honors persisted completion and avoids forcing an upgrade flow onto libraries with records or saved access. Completion validates persisted folder grants and atomically writes automation preferences and the completion record. No schema migration is required.

AppModel restores bookmarks before assessing a saved folder. A folder is shown as connected only if its grant restored (or was selected this session), it is readable and it is a directory. New-library automation stays stopped until completion. Pending defaults never mutate live settings before finishing; login-item registration remains an explicit system action. Progress writes are serialized, paused during setup transactions to prevent stale incomplete snapshots overwriting completion, and flushed on quit. Reopening setup from Settings preserves current defaults and active automation.

OnboardingView uses three lightweight pages with progress/back controls and explicit manual paths. It explains selected-folder access before opening NSOpenPanel, distinguishes local OCR from OS permissions, and describes optional login registration before the toggle. Picker cancellation requests nothing else; failures appear inline and allow retry/manual import. The guide can be reviewed from Settings.

## Outgoing file drags (0.8.2)

Grid, list and inspector use a shared NSItemProvider factory. A per-provider actor lazily copies the original into a UUID directory under Caches/Gather/DragExports, verifies its content hash, and reuses that copy across image-file, URL-object and explicit file-URL data representations. Receivers never receive the library source path. Missing, changed or nonregular originals fail with a visible error. Export copies remain in the app cache; automatic cache eviction is not implemented.

### Native drag correction (0.8.3)

Active library drag surfaces now use FileDragView (NSViewRepresentable), tracking mouse motion after a four-point threshold. On drag start, DragFileExport.copy synchronously creates and verifies an independent cached file, then NSDraggingItem writes the NSURL through AppKit. The dragging source permits copy only. Click selects and double-click opens the image; list checkbox selection remains a separate control. The earlier NSItemProvider factory is retained for compatibility/testing but no longer drives these UI surfaces.

### Onboarding defaults (0.8.8)

All three preferences share explicit checkbox styling and label-first layout. OnboardingState persists launchAtLogin, defaulting true alongside intake/indexing, with backward-compatible missing-field decoding. Review setup restores actual login-service status, preserving existing choices. The final action registers/unregisters only if the pending preference differs, awaits completion and keeps setup visible on errors or newly required OS approval. Manual-import shortcut does not register login service.

## Image fidelity (0.9.4)

ThumbnailCache writes versioned lossless PNG previews, ignoring old JPEG entries. Grid/inspector still downsample to fit their display size. The enlarged viewer uses original(for:) to decode the source directly, retaining original dimensions without the previous 8192-pixel cap or a JPEG round trip. Non-upright EXIF images use native-dimension ImageIO orientation transforms. Source files and drag bytes remain unchanged. Large originals can use more memory; preview caches remain bounded by requested dimensions.
