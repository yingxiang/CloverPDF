# PDF Workflows

## Merge

1. Accept PDFs from file panels, drag and drop, or Finder open events.
2. Require at least two input PDFs. Keep the Merge button disabled for zero or one item and enforce the same guard in `AppModel`.
3. Validate type, reachability, encryption, and page count without modifying the source.
4. Preserve displayed order when inserting pages into the output `PDFDocument`.
5. Ask for the output only when the user clicks Merge. Open `NSSavePanel` in Downloads with a local-time `yyyyMMddHHmm.pdf` default name and allow editing.
6. Write to a temporary PDF, validate its page count, then atomically move or replace the user-confirmed output URL.
7. Clear the submitted merge inputs only after that merge task succeeds; preserve newly added files and keep the list after failure or cancellation.
8. Treat missing passwords, incorrect passwords, corrupt files, cancellation, and write failures as distinct localized errors.
9. Show original input PDF filenames as individual capsule buttons on a dedicated line for each successfully completed merge task. Highlight a filename with system text and text-background colors on hover, and reveal that source file in Finder when clicked.
10. Show a 48-by-60-point Quick Look thumbnail of the merged output for successful merge tasks, matching Merge workspace rows. Use a fixed-size PDF document icon while a merge task is active.

## Convert

1. Preflight the PDF in Swift and warn when pages appear textless.
2. Send a JSON request to one fixed converter process through stdin.
3. Read JSON Lines events from stdout and structured diagnostics from stderr.
4. Cancel by terminating the child process and deleting partial output.
5. Count a free conversion only after a valid DOCX exists at the final output URL.

## Queue

- Use one conversion worker at a time for predictable CPU and memory use.
- Let one failed item finish as failed and continue with the next queued item.
- Persist non-secret task metadata and bookmarks. Mark previously running tasks interrupted after relaunch.
- Never retain PDF passwords in persisted task data.
