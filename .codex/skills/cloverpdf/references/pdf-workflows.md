# PDF Workflows

## Merge

1. Accept PDFs from file panels, drag and drop, or Finder open events.
2. Require at least two input PDFs. Keep the Merge button disabled for zero or one item and enforce the same guard in `AppModel`.
3. Validate type, reachability, encryption, and page count without modifying the source.
4. Preserve displayed order when inserting pages into the output `PDFDocument`.
5. Ask for the output only when the user clicks Merge. Use the `FileSavePanel` subclass pattern from the reference app: assigning PDF, PNG, and JPEG content types installs and retains a standard format popup inside `NSSavePanel`. Start in Downloads with a local-time `yyyyMMddHHmm` base name, then derive and append the extension from the selected `UTType`; never require the user to edit it.
6. Keep PDF as the default. For PNG or JPEG, render every input page through the shared image renderer and vertically combine all pages into one long image in displayed order.
7. Put Batch Convert immediately left of Merge. Keep the native directory-only `NSOpenPanel` and the same retained format accessory used by merge. Disclose the format accessory immediately, then observe that panel's window updates and hide only AppKit's accessory disclosure button after AppKit creates or relays it out, so Show/Hide Options is absent without replacing the native panel. Enqueue one task per input PDF, sharing one batch timestamp, and export one vertically combined image per task using the original base filename with only the selected extension changed.
8. Share PDF loading, password handling, page rendering, image encoding, collision resolution, and temporary-output behavior between long-image merge and batch image conversion.
9. Write each output to a temporary location before moving or replacing the user-confirmed destination.
10. Clear the submitted merge inputs only after that merge task succeeds; preserve newly added files and keep the list after failure or cancellation. Batch conversion does not clear the merge workspace.
11. Treat missing passwords, incorrect passwords, corrupt files, cancellation, and write failures as distinct localized errors.
12. Use the shared file-item layout in task history. Show the actual generated filename as the title, submitted page count and file size on the metadata line, and the output directory on the path line. Put original input PDFs in a horizontal capsule list on the final line and reveal the selected source in Finder when clicked; do not duplicate original filenames beneath the title.
13. Show a 48-by-60-point Quick Look thumbnail of the merged output for successful merge tasks, matching Merge workspace rows. Use fixed-size operation icons while merge or batch-image tasks are active.
14. Use the shared outline-only item selection behavior in the merge workspace, including Command toggle selection and Shift range selection. A context-menu Delete removes the clicked file or every selected file when the clicked file is part of the selection. Show in Finder passes every selected source URL to Finder in one call.
15. Persist the exact collision-resolved output path for each successful batch-image item. Show one raster thumbnail and one target filename per task row. Decode raster thumbnails through ImageIO instead of Quick Look to avoid black previews for long images, and suppress AppKit intrinsic image sizing so previews cannot expand task rows.

## Convert

1. Preflight the PDF in Swift and warn when pages appear textless. Show every page in a variable-height adaptive thumbnail grid, selected by default, and let each green circular check toggle that page independently. A grid drag paints the starting page's new selected or unselected value across every crossed thumbnail. Keep the thumbnail and preview-page checks synchronized, render unselected checks at 50 percent opacity, and navigate the right preview when a thumbnail page number is clicked.
2. Send the selected zero-based page indices as a `pages` JSON array to one fixed converter process through stdin. Pass the array to `pdf2docx` so non-contiguous selections are honored.
3. Read JSON Lines events from stdout and structured diagnostics from stderr.
4. Cancel by terminating the child process and deleting partial output.
5. Count a free conversion only after a valid DOCX exists at the final output URL.
6. Keep the default output folder in Settings; do not show the save path in the conversion workspace footer. Match the merge workspace's single-row footer structure.
7. Use the shared outline-only item selection behavior in Merge, Convert, and Tasks. Support Command toggle selection and Shift range selection in the conversion workspace, including clicks in its lower page-thumbnail grid. A context-menu Delete removes the clicked file or every selected file when the clicked file is part of the selection. Show in Finder passes every selected source URL to Finder in one call.
8. Skip any conversion item whose page selection is empty. Disable Convert when every item has no selected pages, and calculate batch entitlement requirements from only the items that will actually convert.

## Queue

- Use one conversion worker at a time for predictable CPU and memory use.
- Let one failed item finish as failed and continue with the next queued item.
- Let every task row be deleted individually from its context menu. Remove pending and finished tasks directly; cancel and await an active operation before removing its task record.
- Use the shared outline-only item selection behavior in the task list, including Command toggle selection and Shift range selection. Context-menu Delete removes the clicked task or every selected task when the clicked task is selected, cancelling and awaiting the active task before deleting the selected records.
- Include Show in Finder in every task-row context menu. For multiple selected tasks, pass each task's representative URL to Finder in one call. Prefer the first generated output for each task and fall back to its first input.
- Check generated-output availability without blocking the main thread. If the recorded output file has been deleted, strike through the task title, use the secondary text color, and hide Show in Finder from both the row and its context menu.
- Serialize task-repository writes so a late cancellation snapshot cannot restore a deleted task.
- Group task rows into compact, collapsible second-level time sections labeled with `yyyy/MM/dd HH:mm:ss`. A section header delete button confirms before deleting all child tasks; context-menu deletion is immediate, and Show in Finder reveals each representative result. Keep every image produced by one Batch Convert action as its own task row under the same section, and migrate legacy combined batch records during restore.
- Selecting a task opens the shared right-side PDF preview. Prefer a generated PDF output; otherwise preview the first original PDF so image and Word tasks remain inspectable.
- Persist non-secret task metadata, including submitted page count and file size. Keep new fields optional for historical task compatibility, and mark previously running tasks interrupted after relaunch.
- Never retain PDF passwords in persisted task data.
