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

Pandoc selects layouts from the reference PPTX by their standard names. A reference deck intended for general use should retain the standard layouts `Title Slide`, `Title and Content`, `Section Header`, `Two Content`, `Comparison`, `Content with Caption`, and `Blank`. Export is strict: if Pandoc has to warn about a degraded presentation, including a missing required layout, the export fails rather than silently producing a fallback deck.

Column widths are controlled by the PowerPoint layout rather than by an Emacs-side positioning system. Precise visual inspection and the render/preview loop are a later part of the Office workflow.
