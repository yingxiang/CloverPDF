---
name: cloverpdf
description: Develop, fix, refactor, test, or review the WPDF native macOS application in the CloverPDF repository. Use for SwiftUI, AppKit, PDFKit, pdf2docx worker integration, task queues, StoreKit entitlements, the shared Mac paywall, localization, sandbox file access, Finder PDF document registration, App Store builds, and project quality gates.
---

# WPDF

## Start Every Task

1. Inspect the current source before deciding implementation details.
2. Read the relevant reference:
   - Architecture or shared state: `references/architecture.md`
   - Merge, conversion, or task behavior: `references/pdf-workflows.md`
   - Purchases or localization: `references/purchases-localization.md`
   - Finder, sandbox, signing, or distribution: `references/finder-sandbox.md`
3. Treat source code and build configuration as truth. Update this skill in the same iteration when documented facts drift.

## Project Invariants

- Keep the public product name `WPDF`. The repository, Xcode project, target, Swift symbols, converter helper, bundle identifier, signing identities, team, and provisioning profiles retain their existing internal names unless explicitly requested.
- Build a native macOS app with SwiftUI, AppKit, and PDFKit. Keep the Python converter behind a protocol and child-process boundary.
- Keep PDF merging free. Allow three successful single-file PDF-to-Word trial conversions; require premium for batch conversion or further conversions.
- Support `zh-Hans`, `en`, `ko`, `ja`, `de`, and `ru` for every user-visible string.
- Reuse the shared purchase sources under `../common/MacAppKit/Purchases`. Do not create another paywall UI.
- Register `com.adobe.pdf` as a Viewer with `LSHandlerRank=Alternate` so Finder lists WPDF in Open With.
- Keep all PDF processing local. Never upload documents or dynamically download executable code.

## Architecture Rules

- Keep UI free of direct PDF file mutation, StoreKit queries, persistence, and Python process management.
- Put PDFKit merging, conversion, task persistence, trial state, and purchase state behind protocols.
- Own shared mutable task state with an actor or an explicit `@MainActor` owner.
- Never block the main thread with file I/O, PDF parsing, process waits, or bookmark resolution.
- Write outputs to a temporary location and atomically move them into place only after success.
- Never persist PDF passwords or expose them in process arguments. Send secrets through standard input only.
- Preserve user files. Resolve collisions by generating a new name unless the user explicitly confirms replacement.

## Complexity Rules

- Fail when a Swift, Python, or test source file exceeds 1000 physical lines.
- Fail when a function, method, initializer, or Python function exceeds 120 lines.
- Warn at 800 file lines and 80 function lines; split new responsibilities before the hard limit.
- Exclude generated files, String Catalogs, resource manifests, build output, vendored dependencies, and shared-component symlinks.
- Keep control-flow nesting at four levels or fewer when practical. Replace more than six parameters with a request or configuration type.
- Do not compress statements or remove useful whitespace to evade limits.
- Run `python3 .codex/skills/cloverpdf/scripts/check_source_limits.py` before delivery.

## Shared Purchase Rules

- Reference `MacPaywallPresenter.swift` and `MacPurchaseManager.swift` from the common directory through symlinks or direct Xcode file references.
- Add only a CloverPDF coordinator that supplies products, benefits, URLs, entitlement callbacks, purchase callbacks, and restore callbacks.
- Do not redefine `MacPaywallPresenter`, `MacPaywallProduct`, purchase cards, restore UI, or purchase-result UI inside CloverPDF.
- Add missing generic translations to the common component once. Do not fork the public purchase page for a single app.
- Use StoreKit `displayPrice`; never synthesize the current price.

## Localization Rules

- Put user-visible text in `Localizable.xcstrings` or `InfoPlist.xcstrings` in the same iteration as the code.
- Require complete translations for all six supported locales. Do not leave empty or `needs_review` values for active keys.
- Return structured codes from Python and localize them in Swift.
- Use `FormatStyle` for prices, dates, counts, and file sizes. Use plural variations instead of sentence concatenation.
- Implement layouts that accommodate German and Russian long text plus Japanese and Korean line wrapping. Leave visual acceptance to the user under the UI verification rules below.

## UI Verification Ownership

- Treat UI visual and interaction acceptance as user-owned verification.
- Do not independently launch CloverPDF, capture screenshots, inspect windows through accessibility APIs, or run UI automation to validate UI changes.
- Continue to run compiler checks, unit tests, localization completeness checks, source limits, Release builds, and the Skill gates after UI implementation.
- Do not block delivery on visual inspection or ask the user to report UI verification results.
- Perform UI validation only when the user explicitly requests it in the current task.

## Finder And Sandbox Rules

- Keep `CFBundleDocumentTypes` registered for `com.adobe.pdf`, role `Viewer`, rank `Alternate`.
- Route one externally opened PDF to preview/actions and multiple PDFs to a merge workspace without discarding an existing session.
- Persist security-scoped bookmarks for queued inputs and output folders that must survive relaunch.
- Bundle and sign the fixed converter and its libraries. Do not install packages or interpreters at runtime.

## Same-Iteration Skill Sync

Update this skill and the relevant references whenever any of these change:

- Source directories, key files, core types, protocols, product identifiers, or state machines.
- Merge, conversion, task recovery, purchase, localization, Finder-open, sandbox, build, test, or release behavior.
- A path, symbol, command, or invariant documented here no longer matches the repository.

Before delivery run:

```bash
python3 .codex/skills/cloverpdf/scripts/check_source_limits.py
bash .codex/skills/cloverpdf/scripts/verify_cloverpdf_skill.sh
python3 /Users/xiangying/.codex/skills/.system/skill-creator/scripts/quick_validate.py .codex/skills/cloverpdf
```

Include `Skill sync: updated and verified` in the final delivery note. An implementation is incomplete until these checks pass.
