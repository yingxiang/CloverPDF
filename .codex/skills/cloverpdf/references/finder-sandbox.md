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

## User-Managed Signing

- Keep the active application bundle identifier `com.lingchen.pdf` unless the user explicitly changes it again.
- Preserve Team `GBJH26W27R`, Debug profile `pdf_debug`, Release profile `pdf_release`, and their configured signing identities.
- Use `CODE_SIGNING_ALLOWED=NO` only as a command-line build override for local verification; never persist that override into the project.
