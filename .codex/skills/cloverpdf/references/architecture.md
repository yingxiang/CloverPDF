# Architecture

## Layers

- `CloverPDF/App`: lifecycle, dependency composition, commands, and external-file routing.
- `CloverPDF/Core`: models, protocols, localization helpers, file utilities, and persistence.
- `CloverPDF/Features`: merge, convert, tasks, preview, settings, and purchases.
- `CloverPDF/Infrastructure`: PDFKit services, Python process adapter, bookmarks, Keychain, and task storage.
- `converter`: fixed Python entry point and packaging files for `pdf2docx`.

## Ownership

- Keep `AppModel` on `@MainActor` for navigation and presentation state.
- Keep queue mutation in `TaskQueueActor`; publish immutable snapshots back to the UI.
- Keep PDF services stateless where possible and inject them through protocols.
- Keep workspaces independent so Finder-open events never overwrite an active configuration.

## Workspace UI

- Keep the window title synchronized with the selected sidebar section.
- Keep the navigation sidebar fixed at 210 points while expanded so narrowing the window cannot clip or partially hide it. Allow it to collapse from a title-bar toggle that remains available for expansion.
- Put the shared `Add PDF` action in the title bar for Merge and Convert; use the same icon and label in both sections.
- Make the centered empty-state icon in Merge and Convert invoke the same `Add PDF` file-panel flow as the title-bar action.
- Generate row thumbnails with Quick Look so they match Finder's PDF thumbnail style; use the Finder file icon only as a fallback.
- Use native SwiftUI `List.onMove` reordering so the whole row follows the pointer. Do not add custom drag handles or drop delegates.
- Keep row thumbnails inside a clipped 48-by-60-point container with explicit spacing before the text column; include the source directory and provide Move Up, Move Down, Delete, and Show in Finder context actions. Hide both move actions when the list has one item and disable the unavailable direction at list boundaries.
- Use three panes when a file is selected: sidebar, file workspace, and a resizable PDF preview. Collapse the preview when selection is empty and auto-scale PDF pages whenever the preview width changes.
- Put Batch Convert immediately left of Merge. Use a retained `FileFormatAccessory` through the reference-style `FileSavePanel` subclass for merge and disclose the same accessory immediately on the batch `NSOpenPanel`. Center the format label and popup together within the panel while constraining both edges for long localized names; derive extensions from the selected `UTType`, queue both operations, and reuse `PDFPagePipeline` plus `PDFPageImageRenderer` for merged long images and one long image per batch input PDF.
- Render original-PDF path buttons in task rows with `textBackgroundColor` text over a `textColor` capsule. Use 50 percent background opacity normally and 100 percent on hover, without an outline.
- Provide a destructive Delete action in each task row's context menu. Route deletion through `TaskQueueActor`, cancel active work before removal, and keep repository writes ordered.

## Build

- Treat the checked-in `CloverPDF.xcodeproj` as the active project. Do not run XcodeGen or overwrite the user's signing, team, provisioning, or bundle settings unless explicitly requested.
- Keep deployment target at macOS 13 unless the product requirement changes.
- Keep the shared purchase sources as symlinks under `CloverPDF/Features/Purchases/Shared`.
- Build the pinned Python environment with `scripts/build_converter.sh`; Xcode embeds and signs it through `scripts/embed_converter.sh`.
- Build each release on its target architecture so the Swift app and native Python helper match; the current verified artifact is Apple Silicon.
