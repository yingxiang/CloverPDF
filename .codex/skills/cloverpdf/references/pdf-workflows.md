# PDF Workflows

## Merge

1. Accept PDFs from file panels, drag and drop, or Finder open events.
2. Require at least two input PDFs. Keep the Merge button disabled for zero or one item and enforce the same guard in `AppModel`.
3. Validate type, reachability, encryption, and page count without modifying the source.
4. Preserve displayed order when inserting pages into the output `PDFDocument`.
5. Ask for the output only when the user clicks Merge. Use the `FileSavePanel` subclass pattern from the reference app: assigning PDF, PNG, and JPEG content types installs and retains a standard format popup inside `NSSavePanel`. Start in Downloads with a local-time `yyyyMMddHHmm` base name, then derive and append the extension from the selected `UTType`; never require the user to edit it.
6. Keep PDF as the default. For PNG or JPEG, render every input page through the shared image renderer and vertically combine all pages into one long image in displayed order.
7. Put Batch Convert immediately left of Merge. Keep the native directory-only `NSOpenPanel` and the same retained format accessory used by merge. Disclose the format accessory immediately, then observe that panel's window updates and hide only AppKit's accessory disclosure button after AppKit creates or relays it out, so Show/Hide Options is absent without replacing the native panel. Export one vertically combined image per input PDF using the original base filename with only the selected extension changed.
8. Share PDF loading, password handling, page rendering, image encoding, collision resolution, and temporary-output behavior between long-image merge and batch image conversion.
9. Write each output to a temporary location before moving or replacing the user-confirmed destination.
10. Clear the submitted merge inputs only after that merge task succeeds; preserve newly added files and keep the list after failure or cancellation. Batch conversion does not clear the merge workspace.
11. Treat missing passwords, incorrect passwords, corrupt files, cancellation, and write failures as distinct localized errors.
12. Show original input PDF filenames as individual capsule buttons on a dedicated line for each successfully completed merge or batch-image task, and reveal that source file in Finder when clicked.
13. Show a 48-by-60-point Quick Look thumbnail of the merged output for successful merge tasks, matching Merge workspace rows. Use fixed-size operation icons while merge or batch-image tasks are active.
14. Support native multiple selection in the merge workspace. A context-menu Delete removes the clicked file or every selected file when the clicked file is part of the selection. Show in Finder passes every selected source URL to Finder in one call.
15. Persist the exact collision-resolved output paths for successful batch-image tasks. Show up to three same-center thumbnails in a Finder-style front/back fan: the first output is straight in front, with the next two rotated slightly behind it. Decode raster thumbnails through ImageIO instead of Quick Look to avoid black previews for long images, and suppress AppKit intrinsic image sizing so previews cannot expand task rows. Display every target filename as a horizontally scrollable Finder button, and make a single batch task's Finder action reveal its first target.

## Convert

1. Preflight the PDF in Swift and warn when pages appear textless.
2. Send a JSON request to one fixed converter process through stdin.
3. Read JSON Lines events from stdout and structured diagnostics from stderr.
4. Cancel by terminating the child process and deleting partial output.
5. Count a free conversion only after a valid DOCX exists at the final output URL.
6. Keep the default output folder in Settings; do not show the save path in the conversion workspace footer. Match the merge workspace's single-row footer structure.
7. Support native multiple selection in the conversion workspace. A context-menu Delete removes the clicked file or every selected file when the clicked file is part of the selection. Show in Finder passes every selected source URL to Finder in one call.

## Queue

- Use one conversion worker at a time for predictable CPU and memory use.
- Let one failed item finish as failed and continue with the next queued item.
- Let every task row be deleted individually from its context menu. Remove pending and finished tasks directly; cancel and await an active operation before removing its task record.
- Support native multiple selection in the task list. Context-menu Delete removes the clicked task or every selected task when the clicked task is selected, cancelling and awaiting the active task before deleting the selected records.
- Include Show in Finder in every task-row context menu. For multiple selected tasks, pass each task's representative URL to Finder in one call. Prefer the first generated output for each task and fall back to its first input.
- Serialize task-repository writes so a late cancellation snapshot cannot restore a deleted task.
- Persist non-secret task metadata and bookmarks. Mark previously running tasks interrupted after relaunch.
- Never retain PDF passwords in persisted task data.
