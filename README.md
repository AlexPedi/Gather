# Gather

Gather is a native macOS screenshot library. It now **automatically imports screenshots from watched folders, reads their text locally, suggests titles/categories/tags, and groups related images**. Automatic import leaves originals in place. Organize Desktop can move files after an explicit preview. There is no account, server, analytics, or network model.

## Build and run

Requires macOS 14+ and Swift 6.0+ with Apple Command Line Tools or Xcode 16+. Checked with Swift 6.4 on Apple Silicon.

```sh
cd /Users/alex.pedicini/Documents/ChatGPT/Gather
scripts/build-app.sh
open dist/Gather.app
```

Quit and reopen an older running Gather build to load the update. The packaging script creates an optimized host-architecture `.app` with an ad-hoc signature. It omits release debug symbols because this environment blocks `dsymutil`. Debug builds use `CONFIGURATION=debug scripts/build-app.sh`. Open `Package.swift` in Xcode to work on the source.

## Automatic intake and organization

1. Open Gather. A fresh library starts with guided setup: learn what Gather reads, choose a screenshot folder, and select automatic intake, local organization, and optional launch at login. Manual import is available if you skip folder access. Existing libraries keep their defaults; **Settings → Review Guided Setup…** reopens the guide. **Watch Screenshot Folder…** remains available under Import and Settings.
2. New screenshot candidates enter automatically while Gather runs. A file must have the same nonzero size and modification time on two consecutive polls. The current polling interval is three seconds, so a finished screenshot usually appears within roughly 3–6 seconds, plus processing time.
3. Gather reconciles folder contents on launch and on subsequent polls after wake. It catches files added while Gather was quit or intake was paused. Folder contents are immediate, not recursive. Screenshot names and Spotlight screenshot metadata identify candidates; explicit Import accepts arbitrary image filenames.
4. Local Apple Vision OCR reads each image. Text rules assign a category only when multiple distinct terms support a clear winner. For example, insurance, premium, deductible and coverage support Finance. With weak or tied evidence, screenshots remain Uncategorized.
5. Automatic category groups appear in the sidebar. Additional **related groups** require shared OCR words and nearby capture times; **exact duplicate groups** use SHA-256. These are dynamic views and never rearrange files. Select a related/duplicate group, then click **Review Group** to inspect and curate it before saving a normal collection. You can also dismiss the suggestion.

Existing pending screenshots are processed automatically too. Suggested titles use a readable OCR line when possible, otherwise the capture/file date. User-edited titles, categories and tags always win, including during concurrent indexing or changed-file reprocessing. This is text-derived organization, not visual understanding of text-free images.

Settings lets you add/stop watched folders, pause organization, and retry failed OCR. Pausing allows the current image to finish. Stopping a watcher does not remove its imported screenshots or saved file access. Screenshot text never leaves this Mac.

## Review suggested groups

Select a related or duplicate suggestion in the sidebar and click **Review Group…**. The review sheet shows real thumbnails, capture dates, shared words and matching connections (or an exact-duplicate explanation). Click a thumbnail for a larger preview. Edit the collection name and uncheck screenshots that do not belong. **Include All** and **Exclude All** help with larger suggestions; saving requires at least one included screenshot and a name of up to 120 characters.

**Save as Collection** adds only the included images. Excluded screenshots stay in the library. Creating the collection, its memberships, its search documents and the saved review decision is one SQLite transaction; a failed save leaves none of those changes partially applied. Original files are never moved or deleted.

Saving or dismissing remembers the original suggestion. Small membership changes stay suppressed: at least two images must overlap, with a subset or at least 60% Jaccard overlap. Substantially new groups can still appear. Reviewed exact-duplicate content stays hidden even if another identical copy arrives. Existing older exact-ID dismissals are honored too.

Settings → **Show Reviewed Groups Again** resets this suggestion history, including saved suggestions and legacy dismissals. Your collections and screenshot metadata remain intact.

## Dynamic tags and your own tags

The filter row and screenshot cards use **actual tags from your library**, not a fixed list of topics. On-device Natural Language tagging derives up to six nouns, names and keywords from OCR text. This works even when a screenshot's category is uncertain. No tag vocabulary is hardcoded; words such as a destination, a benefits term, a project or a product can become tags. Language-model assets are not requested from a network; when a local lexical model is unavailable, a word-frequency fallback is used.

- Click **New Tag** next to the filter chips (or under Import) to create a reusable personal tag. You can create it before assigning it to any image.
- With a screenshot selected, use the inspector's **+** to choose an existing tag or create one. Remove individual tags with their × controls. The comma-separated editor remains available.
- Tags ignore case and surrounding spaces for duplicate detection. Custom tags allow up to 60 characters, without commas, and persist across relaunch even when not assigned.
- Your manual tag edits are preserved. Previously indexed screenshots refresh their automatic tags from saved OCR text without decoding or recognizing the images again.
- Tag chips show counts; clicking one filters the library. All clears the tag filter. Automatic category and related groups remain separate sidebar views.
- **Manage Tags** opens library-wide rename and merge controls with affected screenshot counts. Renames and merges update the search index and persist aliases for future suggestions. Duplicate memberships collapse to one tag; manual-edit flags remain intact.
- **Hide Automatic Tag** removes a label from automatic assignments and prevents it returning. Manually edited tag lists are preserved. Hidden labels can be allowed again for future suggestions.
- Suggested noun forms consolidate variants such as Child/Children, and common interface words such as Edit/Share are suppressed. Custom tags can still use those words. Existing automatic tags refresh from saved text using tagging version 2; no new OCR pass is needed.

## Everyday use

- ⌘I: native multi-image import; ⇧⌘I: scan a folder with candidate-count review. Drop images or one folder into the library. Explicit scans remain separate from enabling continuous watching.
- Select a grid card or list row to see a larger preview, metadata, editable title/category/tags, favorite/review state, collection memberships, and extracted text with Copy and Retry.
- ⌘F: search titles, original filenames, tags, OCR text and collections. SQLite FTS5 queries are debounced. Content-tag filters, grid/list, adjustable thumbnails and date/title sorting are available.
- Create a collection with ⇧⌘N or the sidebar. Collections are user-managed; automatic groups are computed views.
- Space from the library opens a large downsampled preview. Arrow keys step selection; Escape closes preview. Show in Finder reveals the untouched original.
- Missing originals can retain a cached preview. Use Grant Access to restore permissions, or Locate Original to relink an exact content match.

## Tests

```sh
scripts/test.sh
```

Twelve shared integration scenarios exercise actual SQLite, ImageIO, Vision and Natural Language: reimport, identity, persistence, manual edits, duplicates, per-file failures, thumbnails/cache, conservative classification, related grouping, FTS updates, processing restart, settings persistence, legacy migrations, stable watched-folder intake and dynamic/custom tag behavior. A real rendered text fixture verifies Vision OCR end to end.

The suite needs normal macOS framework access. In a restricted agent sandbox, the Vision test can fail to allocate pixel buffers; run it with permitted native framework access. In this session the twelve checks passed outside that sandbox. XCTest is absent from the installed Command Line Tools. With full Xcode selected, `swift test` runs wrappers around the same scenarios. See [VERIFICATION.md](VERIFICATION.md) for results and remaining checks.

## Storage and permissions

Metadata, bookmarks, OCR text, FTS index and automation preferences live in `~/Library/Application Support/Gather/Library.sqlite` with WAL sidecars. JPEG preview caches live in `~/Library/Caches/Gather/Thumbnails`. Back up the support folder while the app is closed and back up originals separately. Schema version 4 migrates existing libraries without changing screenshot IDs or manual metadata. Do not open the same library in the old version after migrating it; old versions correctly refuse newer schemas.

Gather uses security-scoped bookmarks for selected files/folders. macOS may separately ask for Desktop permission; Full Disk Access is not needed. This direct-distribution build is not App Sandbox enabled. Sandboxed signing, revoked permissions and folder renames still need further testing. Active scopes are balanced on quit. A moved authorized folder may need to be selected again in Settings; individual originals can be relinked from the inspector.

See [ARCHITECTURE.md](ARCHITECTURE.md) for service boundaries, concurrency and recovery details.

## Milestone status

| Milestone | Current status |
| --- | --- |
| 1 · Library | Native import/drop, persistent bookmarks/metadata, grid/list/cache, inspector, favorites, manual collections and source recovery implemented. |
| 2 · OCR/search | Vision worker, persisted queue states, restart recovery, per-file failure/retry, Copy, FTS5, debounce and category/result filtering implemented. |
| 3 · Automatic labels | Conservative text-rule fallback, OCR titles/tags/categories and manual-edit preservation implemented. Optional Foundation Models not integrated; no Apple Intelligence requirement. |
| 4 · Monitoring/grouping | Three-second stable-file polling/reconciliation, changed-file reindexing, exact hashes, duplicate/related groups, save-to-collection and persistent dismissal implemented. Native filesystem event notifications are not used. |
| 5 · Desktop cleanup | Explicit selection, exact-path preview, collision-safe verified moves, per-file results, durable history, recovery and previewed undo implemented. |
| 6 · Polish/packaging | Grid/list/sizing, shortcuts, adaptive colors, automation settings and local bundling/signing implemented. Batch tagging, favorites and collection assignment are implemented. Menu-bar access, optional launch at login and background intake are implemented. Distribution QA remains. |

## Limitations

- Keep Gather running for automatic intake; closing its library window leaves it running. Quit stops intake, and missed files are found when it next runs. Launch at login is optional in Settings.
- OCR/text rules can misread content or choose an imperfect title. Correct any suggestion in the inspector. Text-free images need manual labels.
- Related groups use token overlap and time, not visual similarity or semantic AI. Candidate comparisons are bounded to the preceding 40 recognized screenshots in a 45-minute window. Substantially changed membership can produce a new suggestion; mostly overlapping groups are suppressed after review.
- Screenshot detection is heuristic and nonrecursive. Custom screenshot filenames may need explicit import.
- File stability checks cannot prove an unusual writer has finished if it pauses for more than a polling interval. Corrupt/changing files fail individually; Retry or a later file change can recover them.
- Missing/failed OCR items are not retried endlessly. Permission errors appear in Settings and the inspector; use Grant Access then Retry. Startup folder reconciliation can retry source imports after a restart.
- Replacing image bytes at a watched path triggers reindexing; originals remain untouched. Metadata edits and OCR results merge atomically within the database actor.
- The thumbnail disk cache has no automatic eviction. The library's metadata still loads in memory. The previous synthetic 5,000-record benchmark is not a full image/OCR performance result; 5,000-image interactive responsiveness remains unverified.
- Native event monitoring, visual embeddings, optional Foundation Models, App Store packaging, and collection rename/delete UI remain outside this update.

## Distribution

Local bundles are ad-hoc signed. With a configured Developer ID Application certificate:

```sh
SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' scripts/build-app.sh
codesign --verify --deep --strict --verbose=2 dist/Gather.app
ditto -c -k --keepParent dist/Gather.app dist/Gather.zip
xcrun notarytool submit dist/Gather.zip --keychain-profile YOUR_NOTARY_PROFILE --wait
xcrun stapler staple dist/Gather.app
spctl --assess --type execute --verbose=2 dist/Gather.app
```

No signing credentials were accessed and no notarization was performed. The script builds the host architecture, not a universal binary.

## Organize Desktop (0.5)

Use **File → Organize Desktop…** (also in the Import menu). Choose screenshots from the current view, choose a destination folder, grant source-folder access if requested, and review every source/destination path. Confirm **Move Screenshots** to move them. An occupied destination gets a numbered filename during preview; a file arriving afterward is never overwritten. Automatic intake never initiates moves.

Each destination copy is hashed and verified before its source is removed. The library keeps screenshot IDs, titles, tags, favorites and collection memberships. Partial failures appear beside each file. **File → File Operations… → Preview Undo…** previews restoring completed moves. Undo refuses occupied original names or changed destination contents; resolve the conflict and retry.

Operations and reserved paths are journaled in SQLite. Startup reconciles interrupted moves; File Operations also offers **Check Interrupted Operations** and access recovery. Files that cannot be safely reconciled remain reserved for review, with exact recovery paths shown. Moving requires enough free space for a full copy. External volumes, permission revocation and abrupt power loss still need device-level QA. Back up original files separately.

## Batch actions (0.6)

Click **Select** in the toolbar, then click grid cards or list checkboxes. **Select All** selects the current results; **Clear** deselects them. Use **Favorites** to add/remove favorites, **Edit Tags…** to add or remove an existing/custom tag, or **Add to Collection** to choose an existing collection. Click **Done Selecting** to return to individual inspection.

Changing the search, tags, or sidebar view removes hidden screenshots from the selection. Each batch action changes only its field on the latest records and commits all selected records plus search updates in one transaction. Other tags and metadata are preserved. Tag edits become manual so future automatic suggestions cannot replace them. Adding a custom tag saves it to the reusable catalog. Collection membership is deduplicated. These actions do not move files.

## Background operation (0.7)

Closing the library window keeps Gather running. The **Gather menu bar icon** offers **Open Gather**, intake/organization toggles, Settings and Quit. **File → Open Gather** (Command–0) and reopening the app also bring back the single library window. Quit flushes pending work and stops intake.

**Automatic Screenshot Intake** pauses new folder scans; an in-progress scan may finish. **Automatic Organization** separately controls OCR and labeling. Both settings persist, and resuming intake reconciles missed screenshots.

In Settings, optionally enable **Launch Gather at login**. The toggle reflects macOS registration status; if approval is required, use **Open Login Items Settings…**. Registration failures are displayed rather than treated as success. Keep the app in a stable location before enabling it. The isolated QA bundle disables login registration to avoid modifying system startup settings. Actual launch after signing in still requires device-level verification.

## Opening screenshots (0.7.3)

Double-click a screenshot in the grid, list, or inspector to open a centered white preview sheet over the library, with the screenshot title and a Done button. The image fits with its proportions preserved. Done or Escape returns to the library. Space on a selected screenshot and the Open Image context menu use the same viewer. Batch selection keeps its selection behavior.

## Guided setup (0.8)

New libraries receive a three-step first-run guide: welcome, screenshot folder, and defaults. Folder access is explained before the native macOS picker opens, including why Desktop/Documents access may be requested. Automatic intake leaves files in place. Recognition/search/tagging runs locally and needs no extra permission. Launch at login remains optional and reflects macOS’s actual status, including approval or registration errors.

Setup recommends automatic intake after a folder is granted and local OCR/organization. **Use Manual Import** skips folder permissions; **Set Up Later** on the folder step continues with manual intake. Cancelling the picker keeps setup open, and access problems explain how to reconnect or skip. No automatic scanning or OCR starts in a fresh library until setup completes. Interrupted setup resumes its saved step and choices. Completion and automation preferences commit together.

Libraries that already contain screenshots or file grants keep their configuration. Open **Settings → Review Guided Setup…** to run the guide again. Existing watched folders remain connected when reviewing setup; intake can be paused without removing their grants.

## Zooming previews (0.8.1)

In an opened image, use **Expand preview** for a larger sheet, **+ / −** to zoom, **100%** for actual image size, and **Fit** to show the whole image. Scroll horizontally and vertically while enlarged, or pinch to zoom on a trackpad. Done or Escape returns to the library. The viewer decodes the original image at its full pixel dimensions; library previews use a separate lossless PNG cache.

## Drag images into other apps

Drag an image from a library grid card, list row, or inspector preview into a file-accepting app. Gather shares a verified copy with the original filename, keeping the library original in place. Each drag shares one image. Reopen the rebuilt app to use this feature.

## Review as you browse

Selecting or opening a screenshot marks it reviewed automatically. Reviewed screenshots leave Inbox and remain in All Screenshots. Use arrow keys to navigate the library; grid Up/Down moves by row and Left/Right by image. Space opens the selected screenshot. Batch selection does not mark images reviewed.

## Copy screenshot text

Use **Copy Text** on a grid card, list row, or in the inspector to copy the screenshot’s recognized text. **⇧⌘C** copies text from the selected screenshot, also available as **Edit → Copy Screenshot Text**. The button briefly shows **Text copied** after a successful copy. Copy is disabled when no readable text is available; card and row actions are hidden during batch selection.


## Delete screenshots

Use **Delete Screenshot…** in the inspector or a screenshot’s right-click menu, or press **⌘Delete**. In multi-select, use **Delete…** to delete the selected screenshots. Gather asks for confirmation, then moves the original files to macOS Trash and removes their library entries, collection memberships, and search results. Failed files stay in the library and errors are shown; successful deletions remain completed.

Recover files from Trash in Finder, then explicitly import them to add them back to Gather. Automatic intake remembers deleted source content so it does not immediately reappear. A changed file at the same path can still be imported automatically. Gather refuses to trash an original whose contents changed since import, or one involved in a pending file operation.

Press **Escape** to leave multi-select and clear its selection. Escape in an open sheet continues to dismiss that sheet first.

## Select with the mouse

In the grid, drag from empty space to draw a selection box, or hold the right mouse button and drag across screenshots. While multi-select is active, a regular drag starting on a card also draws a selection box. Hold Shift or Command while starting the drag to add to your existing selection. Right-click a card for **Select Screenshot** / **Deselect Screenshot**, or choose **Select All**. Escape leaves multi-select. Regular card drags outside multi-select continue to export the image into other apps.
