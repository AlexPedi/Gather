# Verification

Checked on October 27, 2026, using the available Apple Silicon Mac running macOS 26.7.1, Apple Swift 6.4, and Command Line Tools. Full Xcode is not installed. The SDK reports macOS 27; the app deployment target is macOS 14. Compiling for macOS 14 does not replace a runtime check on macOS 14 hardware or a VM.

## Automation update · executed results

- Debug and optimized release builds of the automation update passed.
- **All nine integration scenarios passed**, including real Apple Vision OCR on a generated text fixture, category assignment, full-text matching, manual-edit preservation after concurrent/stale metadata saves, durable processing restart, related/duplicate grouping, watched-file stability, changed-source reindexing, reconciliation and migration of a real version-1 schema. Source fixtures and test libraries are temporary.
- The Vision check initially failed inside the restricted execution sandbox with a pixel-buffer allocation error. The identical compiled test executable passed all nine scenarios with permitted native framework access outside that sandbox.
- The original running Gather instance could not be inspected through the native UI tool. A one-second diagnostic sample showed its main thread idle in the event loop; this was not evidence of an OCR deadlock. A separate development bundle with an isolated library was launched for UI verification instead.
- **Native automatic intake: passed.** Selected an isolated watched folder, then created a rendered test screenshot in that folder. It appeared automatically without manual import, received “Hotel reservation confirmation” and Travel, and populated the automatic Travel category group.
- **Native related grouping: passed.** A second distinct but text-similar capture was picked up and automatically grouped as “Related travel screenshots.” Saved that group as a manual collection successfully.
- **Native OCR search: passed.** Searching for a code visible only inside the second image reduced two results to one.
- Initial automation flow checks used an isolated library; the production library was later opened for dynamic-tag verification.
- **Dynamic tag UI: verified in the real library.** The row populated with actual extracted terms such as Coverage and Health Savings Account instead of the fixed category list. The native Create Tag sheet exposes a name field and optional selected-image assignment.
- **Dynamic/custom tags: integration checks passed.** Open-vocabulary extraction from astronomy text, empty-text fallback, case-insensitive deduplication, saved-OCR retagging, persistent unused custom tags, searchable manual tags and preservation of corrections are covered.
- The production library was subsequently opened in the updated app and its original 13 records were preserved; automatic classification and a related Finance group appeared. Continuous intake still requires choosing the user's desired watched folder to authorize that folder.
- No external AI, source deletion or source movement was involved.

## Earlier library build · executed results

- **Debug build: passed.** Built actual SwiftUI/AppKit, SQLite, CryptoKit, Spotlight and ImageIO code.
- **App packaging: passed.** Both debug and optimized release builds produced a locally ad-hoc signed `dist/Gather.app`. The final bundle is the release build.
- **Bundle verification: passed.** `codesign --verify --deep --strict --verbose=2` accepted the signature; `plutil -lint` accepted Info.plist; the executable is arm64 Mach-O.
- **Release build environment:** the first default release attempt failed in `dsymutil` with “Operation not permitted.” Building only the app product with debug symbols disabled completed successfully. The packaging script uses that setting for release builds.
- **Standalone integration suite: passed, 3 scenarios.** Run with `scripts/test.sh`. Both the standalone runner and XCTest wrappers share `Tests/Support/LibraryChecks.swift`.
  - Import, stable ID and idempotent repeat import; title/tags/collection values survive reopening the database; source bytes stay identical.
  - Identical images at two paths retain two records with the same content hash.
  - One corrupt PNG fails independently while another imports; screenshot filename heuristics and candidate scanning; a 1,600-pixel-wide source downsamples to at most 240 pixels in the test; the disk thumbnail cache is populated and read again.
- **XCTest: not run successfully.** `swift test` failed because XCTest is absent from this Command Line Tools installation. Use full Xcode to run those wrappers. Do not interpret the standalone pass as an XCTest pass.
- **Native launch: passed.** Opened the packaged app, observed empty state and the toolbar, sidebar, library, and inspector.
- **Real image import: passed.** Selected the supplied `Gather screenshot library dashboard.png` through NSOpenPanel; one record appeared with a real image preview, 1,586 × 992 dimensions, source path and file size.
- **Editing: passed.** Changed its friendly title to “Gather visual reference” and favorited it. The original filename stayed unchanged.
- **Relaunch: passed.** Quit and reopened the app. The record, title and favorite remained; the file preview was accessible after restoring its permission bookmark.
- **Visual inspection: performed.** Inspected the running light-appearance window after the mockup refinements. The library uses date sections, category chips, a purple selection border and heart favorites. This is not pixel-perfect comparison or full accessibility QA.

The reference image remains an actual imported library record. No generated sample library was injected, and no original files were moved or deleted during verification. Some final UI refinements and quit-flush handling were compiled after the interactive checks; see the remaining checklist below.

## Limited performance measurement

Ran a temporary SQLite library with **5,000 synthetic metadata records** on this Mac:

| Operation | Measured time |
| --- | --- |
| 5,000 inserts with durable per-record commits | 0.4094 s |
| Fetch and decode all payloads | 0.0448 s |
| Case-insensitive title filter and date sort | 0.0060 s |

This was a debug executable and produced 111 matches. It measures metadata storage and a narrow query only. It does **not** measure 5,000 real images, thumbnail cache growth, UI frame times, OCR, launch with revoked grants, or memory under browsing load. Full 5,000-image responsiveness remains unverified.

To reproduce:

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-cache" \
swift run --disable-sandbox --cache-path .build/cache GatherChecks --benchmark
```

## Manual Mac checklist

Use disposable image copies in a temporary folder for tests involving moves outside Gather. Keep original screenshots backed up.

- [x] Launch packaged app and inspect clear empty state.
- [x] Import an explicit PNG using the native picker.
- [x] Select the record; verify its preview, filename, dimensions, date and size.
- [x] Change friendly title and favorite; verify after relaunch.
- [ ] Scan Desktop: inspect candidate count, cancel once, then import an approved set. Re-scan and confirm no repeated records.
- [ ] Import JPEG, HEIC, TIFF and WebP fixtures; drop a batch of images; drop one folder and confirm candidate review appears.
- [ ] With multiple files, check grid/list, date/title sorting, content-tag filters and filename/tag/title searches.
- [ ] Create a collection; add/remove membership through inspector; reopen and confirm membership persists.
- [ ] Check tags, manual category, reviewed/Inbox changes and original file immutability.
- [ ] Use ⌘F, arrow selection, Space preview, Escape dismissal and native tab navigation. Confirm spaces can be typed in titles/search without opening previews.
- [ ] Reveal the exact source in Finder.
- [ ] Temporarily move a disposable source outside Gather. Reselect it: missing state must appear even when a cached thumbnail exists. Locate the identical file; reject a different file; verify a duplicate existing library path cannot overwrite another record.
- [ ] Revoke Desktop permission in macOS settings, relaunch, and confirm an actionable error; grant access again and reselect the image.
- [ ] Rename an authorized folder; confirm unavailable child paths can be recovered with Locate Original. Automatic bulk folder relocation is not implemented.
- [ ] Import enough large images to scroll continuously while hashing. Check browsing/typing responsiveness and memory in Activity Monitor; repeat with approximately 5,000 real images.
- [ ] Resize all three columns and the window; check dark appearance, increased text size/contrast, and VoiceOver labels.
- [ ] Edit a title then immediately quit and relaunch; confirm the final keystrokes persist through the quit-flush delegate.
- [ ] Run on macOS 14, on Intel if distributing to Intel, and under a signed sandbox if adding App Sandbox later.
- [ ] Build with Developer ID and complete notarization/stapling validation before distribution.

## Automation manual checks

- [x] Native selection of an isolated watched folder; real watching status appears.
- [x] Integration test: a stable new image is imported once, repeated polls are idempotent, and a new watcher reconciles without duplicates.
- [x] Integration test: actual Vision recognizes rendered text, assigns Travel and makes recognized words searchable.
- [x] Integration test: a missing image fails independently and the next image completes.
- [x] Integration test: manual title/category/tags survive reclassification and stale UI saves preserve newly extracted text.
- [x] Integration test: pending work resumes after an interrupted processing state; settings persist after reopen.
- [x] Integration test: nearby shared text groups related files, time alone does not, distant images are excluded, and identical hashes group duplicates.
- [ ] Check new captures in the user's actual Desktop folder after restarting the production app.
- [ ] Test denied/revoked permissions, folder moves, wake/sleep and unusual long-pausing writers on a real screenshot destination.
- [ ] Test Settings pause/stop behavior and group save/dismiss interactively.
- [ ] Test approximately 5,000 real images while importing/indexing; the historical synthetic benchmark does not measure OCR or image-heavy UI performance.
- [ ] Test macOS 14 runtime, Intel support if distributed, dark appearance, VoiceOver and signed sandbox behavior.

## Remaining future functionality

Optional Foundation Models, native filesystem event notifications, batch actions, login launch, menu-bar access, physical Desktop cleanup and cleanup undo are not implemented. Cleanup must eventually be verified with collision, partial-failure and undo tests before touching real originals.

## Final packaging

The final 0.2.0 arm64 release compiled successfully after the dynamic-tag card/list and native search-field updates. Its ad-hoc signature passed strict codesign verification and Info.plist passed plutil lint. All nine shared core integration scenarios passed with native framework access. The final native toolbar search-field replacement was compiled but keyboard shortcut behavior still needs a fresh interactive check after restarting the app; no passing keyboard test is claimed.

## Tag quality and management update (0.3)

- All ten integration checks passed with native framework access. Added coverage includes noun consolidation; suppression of interface words; rename, merge and case-only rename; updated FTS; future suggestion aliases; stale manual saves; hidden automatic suggestions; preservation of manual tags; persistent catalog/rules; and reverse aliases without cycles.
- A read-only audit of the existing library examined 13 completed screenshots. All 13 were eligible for refreshed automatic suggestions; none had manually edited tag lists. The proposed unique automatic vocabulary changed from 46 labels to 44, with 21 old low-signal assignments excluded. This is a deterministic metadata audit, not a human-rated semantic accuracy measure, and it made no library changes.
- On the next updated launch, completed automatic tags older than version 2 refresh from saved OCR text. Manual tag lists are protected.
- Manual checks: open Manage Tags from Import or the tag row; rename a tag; merge two tags present on the same screenshot; verify one destination tag remains and search works; relaunch and retry indexing to ensure the old name does not return. Hide an automatic tag and confirm manually tagged screenshots retain it. Allow it again and check future suggestions.

Native tag-management check completed in a separate 0.3.0 bundle with a synthetic library: Manage Tags opened with counts, renaming Children to Family succeeded, and the library chip changed to Family with its assignment retained. The merge destination menu and preview controls were inspected; executing merge is verified by the integration suite rather than a claimed native UI pass. The production library was not edited during this check. The isolated app was sent its normal Quit action afterward.

## Group review update (0.4)

- All twelve integration scenarios passed with native framework access. New checks cover actual grouping evidence, a renamed collection with a selected subset, preservation of excluded records and manual metadata, collection-name FTS matching, durable review history, small/substantial membership changes, duplicate hash suppression, reset without losing collections, invalid inputs and a deliberate SQLite-trigger failure proving collection/membership/FTS/history rollback.
- Native UI checked in an isolated synthetic library: selected a three-image related group, opened Review Group, inspected thumbnails and explanations, renamed it to “Trip options,” excluded one image, and saved the other two. The collection contained two images, All Screenshots still contained three, and the reviewed suggestion disappeared.
- The live user's library was not modified for these UI checks. Existing automatic groups will gain the review controls after restarting the updated production app.
- Remaining manual checks: large preview within the sheet; dense groups with over twenty connections; keyboard and VoiceOver behavior; dark mode; repeated dismissal/relaunch and Settings reset in the native UI. Those backend decision and reset paths are covered by integration tests but are not claimed as completed native UI checks.

## 2026-10-27 · 0.5 cleanup verification

Release build succeeded with scripts/build-app.sh. Ad-hoc signature validation (codesign --verify --deep --strict), Info.plist validation and shell syntax checks passed. GatherChecks built successfully and all **15 integration scenarios** passed outside the restricted sandbox for native Vision/NaturalLanguage access. XCTest wrappers were added; XCTest itself remains unavailable with this Command Line Tools installation.

New scenarios use disposable temporary PNGs only:

- Verified copy/move and reverse transfer; IDs, custom tags, title and favorite preserved. Numbered collision filename preserves the existing destination bytes.
- Occupied original blocks undo without replacing either file; clearing the disposable conflict allows retry.
- Destination arriving after preview fails only that file; another file completes and can be undone.
- Importer defers journal-reserved paths. Interrupted catalogued transfer restores the original database path and removes only its verified app copy. Interrupted completed transfer reconciles the destination and supports undo. Reservations clear after resolution.
- Injected SQLite update failure leaves the original intact; recovery after removal of the injected failure rolls back the owned destination. A foreign destination containing identical bytes survives recovery because its file identity differs from the journaled copy.

Native UI verification for this release is **incomplete**: opening the isolated com.gather.local.tagcheck bundle repeatedly returned macOS accessibility timeout -10005. The bundle was built from the release product with its data-directory override targeting .build/group-review-library. No real user screenshots were moved. New dialogs compile but have not yet been verified through a complete native move/undo interaction. External-volume transfers, abrupt power loss, permission revocation and App Sandbox signing also require device-level QA.

## 2026-10-27 · 0.6 batch actions and native cleanup verification

The previous native UI timeout was resolved on the next run. In the isolated com.gather.local.tagcheck app, selected all three disposable hotel fixtures, chose .build/cleanup-ui-destination, granted the fixture source folder, reviewed exact paths, and moved all three. Each result displayed Moved. Opened File Operations, previewed Undo 3 Moves and confirmed it. All three displayed Restored; filesystem checks confirmed three source PNGs present and an empty destination. No real user screenshots were moved. This completes the previously pending native move/undo check.

The 0.6 release build succeeded. All **16 integration checks passed**, including batch tag alias handling, add/remove tags, favorite values, repeated collection assignment without duplicates, preservation of OCR/path/title/hash, untouched excluded records, FTS, relaunch persistence, invalid/stale selection rejection, and injected database failure rolling back record/catalog/search changes together. XCTest wrappers were added; XCTest remains unavailable in this CLT installation.

Native batch QA used the same isolated library: selected fixtures 3 and 2 in grid, created Batch QA (chip count 2), added favorites (sidebar count 2), added to Trip options (all three members visible), switched to list and confirmed the two matching checkboxes/tags/favorite indicators. Unchecking fixture 3 reduced selection to 1. Searching for unselected fixture 1 reduced selection to 0 and disabled all actions. A screenshot inspection confirmed the batch bar and selection guidance fit the current window.

Device-level external-volume, power-loss, permission-revocation and App Sandbox QA remain outstanding as recorded above.

## 2026-10-27 · 0.7 background operation

Release build succeeded and all **17 integration checks passed**, including decoding older automation preferences with intake enabled by default, preserving independent OCR/review/folder settings, and persisted pause/resume across database reopen. Final ad-hoc signature, Info.plist and shell syntax validation passed. XCTest wrappers exist but XCTest remains unavailable with this CLT installation.

Native checks used com.gather.local.tagcheck with the isolated .build/group-review-library database. Authorized only .build/background-watch-fixtures. Closed the library window, created a synthetic PNG, and confirmed through the isolated database that it imported and completed OCR with content-derived tags while no library window was open. Opened Settings via Command–comma, paused intake and created a second synthetic PNG. It remained unimported over multiple polling intervals, with intakeEnabled=false persisted. Resumed intake and confirmed the second PNG imported and completed OCR. Relaunch showed five records: the original three fixtures plus these two synthetic screenshots.

Added an explicit reopen bridge for Dock/Finder activation and File → Open Gather (Command–0). Verified the File command exists in the final release-derived test bundle. Clicking the library close button and then pressing Command–0 recreated the identified library window with all five records and active watcher status intact. The isolated test bundle was refreshed after a stale-app automation warning before repeating this check.

The Settings login toggle correctly displays disabled/off in isolated development bundles, which deliberately cannot register login items. Actual production login-item enable/disable, approval and next-login execution were not exercised; the user's startup settings were not changed. The MenuBarExtra scene and actions compile, but direct clicks on the status item remain unverified because this automation surface did not expose the menu bar extra. The shared intake controls were exercised through Settings. Long-duration App Nap/sleep/wake and signed distribution QA also remain device-level checks.

## 2026-10-27 · 0.7.1 app icon

Created Assets/GatherIcon.png with the built-in image generation tool: a purple rounded tile and gathered screenshot cards. Original artwork is a square 1254-pixel RGBA PNG; prompt and provenance are saved in Assets/README.md. scripts/build-icon.sh derives the ten standard/Retina representations from 16 through 1024 pixels and encodes Gather.icns. Packaging sets CFBundleIconFile and includes the resource before signing.

The restricted sandbox rejected native iconutil encoding with Invalid Iconset despite valid resized PNGs. Running the same build outside the restricted sandbox succeeded. Verified the resulting ICNS container length and all ten representation types, bundle icon reference, release version 0.7.1/build 8, code signature, plist and script syntax. No app logic changed; integration tests were not rerun for this packaging-only update. Existing running instances may retain their cached icon until relaunched.

## 2026-10-27 · 0.7.2 image windows

Implemented double-click opening in grid, list and inspector using a separate AppKit image window. The final behavior is a normal resizable preview: no automatic native full-screen transition. Space, the View command and group review previews share the image viewer. Existing library layout/selection are retained; image aspect ratio is preserved against a dark background. Escape and Close dismiss the viewer. Batch-selection gestures do not open images.

Release build succeeded. In the isolated test bundle, double-clicked Hotel reservation 3 in grid and visually confirmed a regular 1100-pixel-wide window with native title bar and controls; Escape returned to the library with Hotel reservation 3 selected. Switched to list, double-clicked Hotel reservation 2 and verified the matching image window; its Close button returned to the library with that row selected. Core services were unchanged, so the integration suite was not rerun for this UI-only change. Final code-signature and plist validation passed.

## 2026-10-27 · 0.7.3 reference-style preview

Replaced the separate dark AppKit viewer with a centered 700×550-point white SwiftUI sheet matching the supplied reference: title at top left, Done at top right, aspect-fit image, and the library behind it. Double-clicks, Space and Open Image share the presentation. Group review presents the same sheet from its existing modal to avoid conflicting root presentations.

Release build passed. In the isolated app, double-clicked Hotel reservation 3 in the library grid and inspected the native sheet screenshot: white background, title, Done and image all present. Done dismissed the sheet to the same library and selected screenshot. Final code signature and plist checks passed. No core services changed; the integration suite was not rerun for this presentation-only update.

## 2026-10-27 · 0.8 guided onboarding

Release build passed and all **19 integration checks passed**. New checks cover fresh-library eligibility, saved-step/default resume, manual completion, existing-library preservation, rejecting automatic intake without folder grants, real disposable-folder bookmarks, atomic completion, and injected preference-write failure rolling back defaults/completion together. XCTest wrappers were added; this CLT installation still cannot execute XCTest.

Native inspection used an empty isolated library. Confirmed automatic first-run welcome, the three-step progress indicator, manual import option, folder rationale before requesting access, Continue disabled without a readable grant, Set Up Later and the final preferences page with recommended defaults, local-processing explanation and optional login rationale. The isolated bundle disables login-item mutation. Native automation reported concurrent app changes during folder-picker testing; after refreshing, the chosen-folder flow had reached the final defaults screen. No further UI changes were sent while that interaction was active. Picker cancellation/OS-denial and production login approval were not fully exercised through native automation; core grant/failure validation is covered by the integration checks.

Final code-signature, plist and build-script syntax checks passed. No source files were moved by onboarding or its checks.

## 2026-10-27 · 0.8.1 preview expansion and zoom

Added an expanded sheet size, zoom in/out, actual-size 100%, Fit, two-axis scrolling and trackpad magnification. The image is decoded independently of the grid thumbnail at up to its original dimensions, bounded to 8192 pixels. Zoom ranges from 5% to 800%; Fit automatically adapts to the viewport and preserves aspect ratio.

Release build succeeded. Native testing used the disposable hotel screenshot library through com.gather.local.automationcheck, preserving the other running app's library. Stale cross-bundle bookmark warnings appeared and were dismissed; the synthetic images remained readable. Verified grid double-click opened a 42% fitted image, 100% activated both scroll directions, Zoom In changed to 125%, and Fit plus Expand enlarged the sheet and increased fit to 67%. Screenshot inspection confirmed readable image detail and the toolbar. Done returned to the library. Pinch magnification is implemented but not directly exercised by the available automation API. Core services were unchanged; no integration-suite rerun was needed. Final signature and plist checks passed.

## 2026-10-27 · 0.8.2 outgoing drags

Release build succeeded; all 20 integration checks passed. Disposable fixtures verify original filenames, exact image bytes, cached export reuse, regeneration after a receiver moves its copy, image-file and file-URL representations, and rejection of stale/missing originals. The original remains unchanged. Added XCTest wrapper; this CLT environment still cannot execute XCTest. Cross-app pointer dragging has not been exercised in native UI; destination-specific behavior remains a manual check.

## 2026-10-27 · 0.8.3 native file drag correction

User reported failure dragging into Google Docs after the version update. Replaced SwiftUI onDrag on grid/list/inspector with an AppKit mouse-tracking overlay and NSDraggingSession. It writes a verified copied file using NSURL pasteboard writing and advertises copy-only operations. Build/signature and all 20 integration checks passed. Installed in /Applications and reopened the 21-image library. Native drag automation on the isolated fixture app failed with windowNotFoundAtPosition before mouse dispatch, so pointer drag and Google Docs insertion remain unverified; do not claim end-to-end success.

## 2026-10-27 · 0.8.4 onboarding voice

Updated onboarding copy to reuse the landing-page headline and exact product description, and align folder/default introductions with its language. Permission purposes, local-processing disclosures, original-file behavior and login controls remain explicit. Release build and signature verification passed. Installed and reopened guided setup; native accessibility and screenshot confirm the new welcome text, all three explanations and both footer actions fit visibly in the existing sheet. No behavior changes or integration-suite rerun.

## 2026-10-27 · 0.8.5 onboarding actions

Primary CTA now uses a large purple labeled button with directional icon and step-specific text. Unconnected folder step invokes the existing picker directly instead of disabling Continue; connected folders advance with Use This Folder. Manual import and skipping use secondary link styling. Build and signature passed. Installed app native screenshot verified visible enlarged Set Up Gather action and manual alternative; clicking advances to the connected-folder step with Use This Folder, Change Folder, Back and Skip for Now. Folder picker and completion services are reused unchanged. No integration-suite rerun for this UI change.

## 2026-10-27 · 0.8.7 onboarding readability

Increased caption explanations to 14 pt, body to 15 pt and explanation headings to 16 pt. Secondary copy now uses primary color at 75% opacity for stronger contrast, with three-point line spacing and a 640×710 setup sheet. Release/signature passed. Installed and visually checked step 3: all explanations, login status and footer actions fit without clipping. Native interaction changed concurrently while advancing, so refreshed state and limited further work to reading the displayed final step. No automation toggles or setup completion were invoked by the agent.

## 2026-10-27 · 0.8.8 consistent checked defaults

Release/signature verification and all 20 integration checks passed, including new assertions for all-three checked defaults, legacy state decoding and persisted login opt-out. Installed app bundle updated. Native review was interrupted by concurrent user navigation/completion; stopped driving the flow rather than changing preferences. New login registration/approval failure handling is implemented but not exercised against live macOS registration in this check.

## 2026-10-27 · 0.8.9 selection-only inspector

Replaced the always-present third navigation column with a selection-bound native inspector. Empty selection and batch mode omit details; closing the inspector clears single selection. Build/signature passed. Installed/reopened native app: no Details or placeholder panel, library reached the window edge (splitter 1380). Selecting a screenshot displayed its Details panel and adjusted the library width (splitter 1059). No persistence or core-service change; integration suite not rerun.

## 2026-10-27 · 0.9.0 viewed review and arrows

Selection and explicit image opening mark unreviewed records reviewed through the existing serialized metadata writer; batch selection does not. Library receives initial keyboard focus and regains it after selecting. Grid arrows use measured column count; list arrows use one-row steps. Grid scrolls selection into view. Empty Inbox now says all caught up. Native disposable five-image library: click + Right reduced Inbox 5→3, Down moved one grid row to the expected final image and reduced to 2; Inbox click + Right reviewed the remaining two. SQLite confirmed all five persisted inbox=false after quit. Production rebuild/signature passed and 0.9.0 installed/reopened. List-specific pointer/arrow testing and scrolling beyond the small fixture were not separately exercised. Core persistence engine unchanged; integration suite not rerun.

## 2026-10-27 · 0.9.1 prominent search

Moved search from the toolbar to a full-width 52-point outlined field beneath the library heading, with 17-point input, clear text-search hint and clickable Command-F badge. Release/signature passed and app installed. Native screenshot confirms layout. Command-F focused the new field; typing a disposable no-match query produced zero results while keeping search focused, and clearing it restored the library. Search engine unchanged; integration suite not rerun.

## 2026-10-27 · 0.9.2 search spacing

Replaced the borderless NSSearchField cell with a single-line NSTextField and a separately laid-out SwiftUI magnifying glass. The field keeps 17-point type, Command-F focus, immediate query binding and explicit clear button; Escape clears through its delegate. Build/signature passed and installed app screenshot confirms the icon no longer overlaps the placeholder. Native Command-F/type produced no-match results and a clear button; Escape restored an empty query. Search core unchanged; no suite rerun.

## 2026-10-27 · 0.9.3 visible Import menu

Replaced the custom white-on-purple borderless toolbar Menu with the native bordered menu, explicit title-and-icon label and visible disclosure indicator. Build/signature passed. Installed/restarted app screenshot confirms + Import and chevron visibly render. Clicking opens the existing import/scan/watch/organize/actions menu. No core behavior change; suite not rerun.

## 2026-10-28 · 0.9.4 original quality

Build/signature passed; all 20 integration scenarios pass. Expanded thumbnail scenario verifies normalized decoded pixel equality on PNG cache round trip, exact original dimensions/pixels, ignoring obsolete JPEG cache entries, and original width 9001 with alpha pixel equality (no 8192 cap). Native installed app was restarted after closing the previous viewer, then selecting and Space opened the original-file viewer at 70% Fit. This confirms UI loading, not a subjective before/after quality comparison. New preview ZIP integrity passed.
