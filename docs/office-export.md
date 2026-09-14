# Office export from Org

Org is the editable source. DOCX and PPTX are generated handoff artifacts, not files to edit and round-trip back into Org.

Use `C-c E` in an Org buffer and choose Word or PowerPoint. `#+EXPORT_FILE_NAME` controls the generated filename.

Project-specific Office styling comes from Pandoc reference files. Set `p3-org-export-reference-docx` or `p3-org-export-reference-pptx`; projects can override either variable with directory-local settings. A prefix argument to `C-c E` selects a one-off reference file.

## PowerPoint authoring convention

Use a level-1 heading for a section and level-2 headings for slides:

```org
* Section
** Slide title
- First point
- Second point
```

Ordinary Org tables and local images can be used directly. Relative image paths are resolved from the Org file's directory.

Speaker notes use Pandoc's `notes` special block:

```org
#+begin_notes
Presenter-only note.
#+end_notes
```

Two-column content uses Pandoc's `columns` and `column` special blocks:

```org
#+begin_columns
#+begin_column
Left column.
#+end_column
#+begin_column
Right column.
#+end_column
#+end_columns
```

Keep these special-block names lowercase. Pandoc preserves the Org special-block class name, while its PowerPoint writer recognizes the lowercase `notes`, `columns`, and `column` classes.

Pandoc selects layouts from the reference PPTX by their standard names. A custom reference deck used by this workflow must retain all seven standard layouts Pandoc expects: `Title Slide`, `Title and Content`, `Section Header`, `Two Content`, `Comparison`, `Content with Caption`, and `Blank`. Pandoc resolves these layouts from the reference deck up front; a missing standard layout can therefore trigger a warning even when that layout is not used by the current presentation.

Office export is intentionally strict: any Pandoc warning causes the export to fail. This prevents a missing layout, missing asset, or other warning-driven degradation from being reported as a successful handoff artifact. If Pandoc's warning policy later proves too broad in normal use, narrow it based on a concrete benign warning rather than silently accepting degraded output.

Column widths are controlled by the PowerPoint layout rather than by an Emacs-side positioning system. Precise visual inspection and the render/preview loop are a later part of the Office workflow.

## Incoming DOCX inspection

Use `M-x p3/office-import-docx` when the useful semantic content of a Word file needs to be recovered for inspection or continued editing in Emacs. `report.docx` becomes a sibling `report.org`, with embedded media extracted beside it under `report-media/`.

This is deliberately a content-recovery path, not a preservation path for Word-specific semantics. Custom Word style identities and review metadata such as tracked changes and comments are not retained as reliable Org structure. The generated Org starts with a durable warning that makes those losses explicit and records any Pandoc diagnostics produced during conversion. Keep the original DOCX as the fidelity reference for styling, review history, layout, text boxes, and native Office objects.

The importer refuses to overwrite an existing sibling Org file or media directory. Extracted-media links remain relative so the imported Org, DOCX, and media directory can move together without embedding machine-specific paths.

This is an inspection and editing workflow, not a promise that arbitrary DOCX files can be converted to Org and regenerated identically.
