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

## Build

- Treat `project.yml` as the editable XcodeGen source of truth and regenerate `CloverPDF.xcodeproj` after project membership changes.
- Keep deployment target at macOS 13 unless the product requirement changes.
- Keep the shared purchase sources as symlinks under `CloverPDF/Features/Purchases/Shared`.
- Build the pinned Python environment with `scripts/build_converter.sh`; Xcode embeds and signs it through `scripts/embed_converter.sh`.
- Build each release on its target architecture so the Swift app and native Python helper match; the current verified artifact is Apple Silicon.
