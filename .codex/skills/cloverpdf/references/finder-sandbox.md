# Finder, Sandbox, And Distribution

## PDF Registration

Register `CFBundleDocumentTypes` with:

- `CFBundleTypeName`: `PDF Document`
- `CFBundleTypeRole`: `Viewer`
- `LSHandlerRank`: `Alternate`
- `LSItemContentTypes`: `com.adobe.pdf`

Receive external URLs through `NSApplicationDelegate.application(_:open:)`. Open one PDF in preview/actions and multiple PDFs in a merge workspace.

## Sandbox

- Enable `com.apple.security.app-sandbox`.
- Enable `com.apple.security.files.user-selected.read-write`.
- Enable Downloads read-write access for the default output folder.
- Start and stop access to security-scoped URLs around every operation.
- Persist bookmarks only when access must survive relaunch.
- Use the application container for temporary files and task metadata.

## Converter Distribution

- Package a fixed `cloverpdf-converter` with all Python dependencies.
- Sign nested libraries and the helper before signing the main application.
- Do not download Python, wheels, scripts, or executable code at runtime.
- Resolve PyMuPDF commercial licensing before closed-source App Store distribution.
