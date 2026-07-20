# Architecture

## Layers

- `CloverPDF/App`: lifecycle, dependency composition, commands, and external-file routing.
- `CloverPDF/Core`: models, protocols, localization helpers, file utilities, and persistence.
- `CloverPDF/Features`: merge, convert, tasks, preview, settings, and purchases.
- `CloverPDF/Infrastructure`: PDFKit services, Python process adapter, bookmarks, Keychain, and task storage.
- `converter`: fixed Python entry point and packaging files for `pdf2docx`.
- `pages`: public, dependency-free GitHub Pages content for CloverPDF support and privacy, including a copied app-icon asset.

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
- In Merge, use native SwiftUI `List.onMove` reordering so the whole row follows the pointer. In Convert, make only the upper file-details area a reorder drag source and use each complete card as its drop target, leaving the lower page-selection area available for range painting.
- Keep row thumbnails inside a clipped 48-by-60-point container with explicit spacing before the text column. Reuse `PDFItemDetails` across Merge, Convert, and Tasks so filename, page-count/file-size metadata, path wrapping, spacing, and typography stay aligned. Provide Move Up, Move Down, Delete, and Show in Finder context actions. Hide both move actions when the list has one item and disable the unavailable direction at list boundaries.
- Use the shared item selection component across Merge, Convert, and Tasks: keep the native List row background, replace the system blue selection fill with a 2-point accent-color outline using a 10-point corner radius, and preserve Command toggle selection plus Shift range selection. Keep the standard 74-point Convert file row on top and a variable-height adaptive page-thumbnail grid below it, apply the same item-selection interaction to both halves, and apply a rounded background only to the floating reorder drag preview. Store zero-based selected page indices on each `WorkspacePDF`, select every page by default, and use an 18-point green circular check indicator centered at the bottom of each thumbnail; render the unselected indicator at 50 percent opacity. Put the page number below the indicator, use it to navigate the right preview, and mirror the same selection control at the top-left of every preview page. Let users paint a shared select or deselect value across every thumbnail crossed by a lower-grid mouse drag.
- Use three panes when a file is selected: sidebar, file workspace, and a resizable PDF preview. Collapse the preview when selection is empty and auto-scale PDF pages whenever the preview width changes.
- Keep only two document-processing sections in the sidebar: Merge and Convert. Tasks and Settings remain supporting sections. Keep sidebar rows compact and show localized Merge and Convert format descriptions as hover tooltips instead of visible subtitles. Merge turns multiple PDFs into one PDF, long PNG/JPEG, or DOCX selected in the save panel. Convert turns each input PDF into its own selected-page PDF, DOCX, or long PNG/JPEG selected in the directory panel. Keep separate Merge and Convert workspace state, and route former batch-image behavior through Convert.
- Use a retained `FileFormatAccessory` through the reference-style `FileSavePanel` subclass for merge and disclose the same accessory immediately on the conversion directory `NSOpenPanel`. Display only uppercase filename extensions (`PDF`, `PNG`, `JPG`, `DOCX`) in format popups instead of localized system type descriptions. Center the format label and popup together, derive extensions from the selected `UTType`, queue both operations, and reuse `PDFPagePipeline` plus `PDFPageImageRenderer` for merged long images and one long image per converted input PDF.
- Keep the task list at least 420 points wide when its preview is visible, which is twice the fixed 210-point navigation sidebar. Give the list and preview balanced expansion priorities. Keep the normal task selection outline in the system control accent color. Use the primary text color only for contextual-menu emphasis, and inset the task content shape so AppKit's wider contextual outline shares the same outer boundary as the 2-point selection outline.
- Render original input PDF buttons in a horizontal list at the bottom of task rows, using `textBackgroundColor` text over a `textColor` capsule. Use 50 percent background opacity normally and 100 percent on hover, without an outline.
- Provide a destructive Delete action in each task row's context menu. Route deletion through `TaskQueueActor`, cancel active work before removal, and keep repository writes ordered.
- Group `TasksView` rows by second using `TaskSectionModel`, with a compact, collapsible `yyyy/MM/dd HH:mm:ss` header. Render the localized task type as an 18-point capsule: Merge `#FBC03A`, Batch Image `#62B4E8`, and PDF to Word `#9FD446`. The header delete button confirms before deleting every task in the section; its context menu deletes without confirmation and can reveal all section results in Finder. Split Batch Convert into one queue record per input while assigning the same `createdAt` so the results stay in one section. Persist input page count and file size with each new task, show the actual generated filename as the title, omit the completed-state label, and place original input PDFs on the final horizontal row after metadata and the output path. Check recorded outputs off the main thread; when an output has been deleted, render its title with a strikethrough and secondary text color, and hide both row-level Show in Finder actions. Selecting a task opens the shared resizable PDF preview pane, preferring a PDF output and falling back to the original PDF.

## Build

- Treat the checked-in `CloverPDF.xcodeproj` as the active project. Do not run XcodeGen or overwrite the user's signing, team, provisioning, or bundle settings unless explicitly requested.
- Keep deployment target at macOS 13 unless the product requirement changes.
- Keep the shared purchase sources as symlinks under `CloverPDF/Features/Purchases/Shared`.
- Build the pinned Python environment with `scripts/build_converter.sh`; Xcode embeds and signs it through `scripts/embed_converter.sh`.
- Build each release on its target architecture so the Swift app and native Python helper match; the current verified artifact is Apple Silicon.
