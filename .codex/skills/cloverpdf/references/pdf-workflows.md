# PDF Workflows

## Merge

1. Accept PDFs from file panels, drag and drop, or Finder open events.
2. Validate type, reachability, encryption, and page count without modifying the source.
3. Preserve displayed order when inserting pages into the output `PDFDocument`.
4. Ask for the output only when the user clicks Merge. Open `NSSavePanel` in Downloads with a local-time `yyyyMMddHHmm.pdf` default name and allow editing.
5. Write to a temporary PDF, validate its page count, then atomically move or replace the user-confirmed output URL.
6. Clear the submitted merge inputs only after that merge task succeeds; preserve newly added files and keep the list after failure or cancellation.
7. Treat missing passwords, incorrect passwords, corrupt files, cancellation, and write failures as distinct localized errors.

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
