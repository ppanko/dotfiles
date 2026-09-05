# Emacs-owned reference management design

## Purpose

Build a citation and bibliography workflow that acts as part of the Emacs/Org second brain rather than as a thin front end to an external reference manager.

The durable knowledge model must remain portable and bootstrappable from ordinary files. Packages may provide acquisition, search, citation, note, and PDF-reading interfaces, but no package-specific database may become authoritative.

The system must make common reference operations easier than the current ad hoc BibTeX/RefTeX/Citar configuration. If an added package does not create a distinct ergonomic capability, it should not remain in the design.

## Design goals

The system must support these common workflows:

1. Save an interesting publication when only a URL, DOI, title/search result, or complete citation is available.
2. Keep general-interest references without forcing a project assignment.
3. Search the entire reference library by title, author, year, topic, or status.
4. Search the references associated with a particular Org-roam project.
5. Insert an existing reference into an Org document using native Org citation syntax.
6. Open or create an Org-roam literature note for a reference.
7. Open a locally stored PDF when one is available.
8. Remain useful on a fresh machine even when PDFs or optional packages are absent.
9. Preserve enough plain-text state that another Emacs package stack could replace the current one without migrating the corpus.

## Architectural principle

The system of record is ordinary text plus ordinary files:

```text
references.bib
org-roam/
papers/
```

`references.bib` is the canonical bibliographic database. Org files are the canonical knowledge and relationship graph. PDFs are optional binary attachments.

The package stack is an interface over that state:

```text
                 references.bib
                      |
              +-------+-------+
              |               |
            Citar          Org-cite
        search/actions    citation syntax
              |               |
              +-------+-------+
                      |
                  Org-roam
               literature notes
                      |
                 pdf-tools
                 PDF reading

biblio.el -> acquisition/enrichment -> references.bib
```

No package-specific database is required to reconstruct reference identity, citations, literature-note links, or project associations.

## Durable data model

### Bibliography

Use one canonical BibLaTeX file, configured outside the dotfiles repository. A likely layout is:

```text
~/org/
  references/
    references.bib
  roam/
```

The exact root remains user-configurable. The bibliography belongs with user knowledge data, not with Emacs configuration.

Each mature reference has a stable citekey and normal bibliographic fields such as title, author, year, publication/venue, DOI, and URL when known.

Bibliography keywords may express properties of the source or the user's global relationship to it, for example:

```text
quantitative-methods
record-linkage
causal-inference
status/inbox
status/to-read
status/read
```

Project membership is deliberately not stored as bibliography metadata.

### Citekeys

The citekey is the stable join across the system:

```text
BibLaTeX        @fellegi1969
Org citation    [cite:@fellegi1969]
Literature note :ROAM_REFS: @fellegi1969
PDF directory   ~/papers/fellegi1969/
```

A provisional URL-only inbox record may have a temporary key, but it cannot become part of the durable knowledge graph until the key is finalized. A provisional reference cannot be cited, receive a literature note, be associated with a project, or receive a citekey-based PDF attachment directory.

Finalization uses a deterministic BibTeX autokey convention based on mature bibliographic metadata. The proposed permanent key is shown before it is accepted and may be edited at that point. The exact author/year/title formatting convention is configuration, not corpus structure.

After finalization, citekeys are effectively immutable. Changing one is an explicit migration operation, never a side effect of enrichment.

### PDFs

PDFs remain outside Git and outside the bibliography's consistency model.

Use a configurable attachment root and a deterministic citekey-based layout:

```text
~/papers/
  fellegi1969/
    main.pdf
  smith2024/
    main.pdf
    supplement.pdf
```

Only the attachment root is machine-specific. The bibliography and Org corpus must remain usable when the PDF root or a particular attachment is absent.

If an attachment operation is requested for a provisional record, the record must be finalized first so the attachment path never depends on a temporary citekey.

### Literature notes

A bibliography entry does not automatically create an Org-roam note.

When a source becomes worth thinking about, create one Org-roam literature note with a durable reference property:

```org
:PROPERTIES:
:ID: ...
:ROAM_REFS: @fellegi1969
:END:
#+title: Fellegi & Sunter — A Theory for Record Linkage
#+filetags: :literature:
```

The bibliography owns bibliographic facts. The literature note owns the user's interpretation, summary, questions, arguments, and links to other notes. Avoid duplicating large amounts of bibliographic metadata into the Org note.

## Project associations

Project relationships belong in the Org knowledge graph, not in `references.bib`.

A machine-readable `project` Org-roam tag identifies project notes. Each project note uses one top-level `* References` subtree as the canonical explicit association list:

```org
#+title: SAIDS
#+filetags: :project:

* References

[cite:@fellegi1969]
[cite:@smith2024]
```

The reference workflow creates the `* References` subtree when necessary and keeps associations unique. `C-c b r` reads this subtree, rather than treating every narrative citation elsewhere in the project note as an automatic project association.

This keeps ordinary prose citations semantically distinct from the explicit project-reference registry while leaving the registry itself as plain Org citation text.

One reference may therefore relate to zero, one, or many projects without duplicating or modifying the bibliographic record.

If the current note is not unambiguously a project, project-aware commands prompt rather than guessing.

Project association and literature-note creation remain independent. A project may associate a reference that has no literature note.

## User-facing workflow contract

Expose one stable reference prefix, initially `C-c b`. Package-specific commands should remain implementation details.

### `C-c b a` — add reference

Accept the material the user already has rather than forcing a capture mode first.

Recognize these inputs:

- DOI -> metadata lookup;
- BibTeX/BibLaTeX -> normalize and import;
- URL -> attempt enrichment, otherwise save URL-only;
- ordinary title/author text -> bibliographic search.

Capture follows **save first, enrich second**. Network or metadata lookup failure must not prevent saving a URL-only inbox record.

Google Scholar is treated as an import source, not as a scraped dependency. The supported low-friction path is Scholar's BibTeX export copied into `C-c b a`.

### `C-c b f` — find reference

Fuzzy-search the complete library by useful bibliographic fields and keywords.

This is the central retrieval interface. A selected reference exposes actions such as:

- insert citation;
- open PDF;
- open URL;
- edit bibliography entry;
- open/create literature note;
- associate with a project.

Citar is the preferred implementation of this completion/action layer because it is an interface over standard bibliography data rather than a separate reference database.

### `C-c b i` — insert citation

Search the same library and insert native Org citation syntax, e.g.:

```org
[cite:@fellegi1969]
```

Documents must not depend on Citar-specific citation syntax.

If the selected record is still provisional, citation insertion first enters the explicit finalization flow.

### `C-c b n` — literature note

Select a reference or use the reference at point.

- If the selected record is provisional, finalize it first.
- If a literature note with the corresponding `ROAM_REFS` already exists, open it.
- Otherwise create exactly one minimal Org-roam literature note and place point in the body.

Repeated invocation must not create duplicate literature notes.

### `C-c b p` — open PDF

Resolve the selected citekey to its attachment directory and open `main.pdf` when present.

If the selected record is provisional and an attachment is being added, finalize it first. Missing attachment root or PDF is a normal condition, not a knowledge-base error.

### `C-c b t` — classify or associate

Provide reference classification actions without requiring raw BibLaTeX editing.

The action may:

- add/remove bibliography topic or status keywords;
- associate the reference with an Org-roam project;
- remove an existing project association.

Project association modifies only the canonical `* References` subtree in the project note, not the bibliography entry. A provisional record is finalized before project association.

### `C-c b r` — references for current project

When invoked from an Org-roam project note:

1. identify the current project note;
2. read citekeys from its canonical `* References` subtree;
3. resolve them against `references.bib`;
4. show that subset through the same reference-search/action interface as global lookup.

If the current context is not an unambiguous project, prompt for a project note.

### `C-c b l` — library

Provide a full-library browsing entry point. It should reuse the same reference candidates and actions as `C-c b f`, not create a second database UI.

## Capture and enrichment

Use `biblio.el` where it provides stable bibliographic search/lookup functionality, especially DOI/title lookup through sources such as Crossref. Do not reimplement remote metadata protocols in `p3-reference.el`.

Enrichment may run opportunistically during capture and explicitly later.

Preferred lookup order for an incomplete record:

1. DOI when present;
2. metadata available from the URL through a supported resolver;
3. title search;
4. manual editing.

Enrichment may fill blank fields automatically. It must not silently overwrite populated user data when the retrieved value differs materially.

### Duplicate handling

Before adding a mature record:

1. exact normalized DOI match is a strong duplicate;
2. exact normalized URL match is a strong duplicate;
3. title similarity is only a warning and never an automatic merge.

Strong duplicates should lead to the existing record rather than add a second copy.

The design prefers a visible possible duplicate over an incorrect automatic merge.

## PDF reading and annotations

`pdf-tools` belongs in the initial subsystem because the intended workflow includes reading stored papers in Emacs and opening them from reference actions.

Precise source-linked annotation is deferred from v1.

A later annotation layer may use `org-noter`, and possibly `org-pdftools` if exact annotation identifiers/regions provide a demonstrated benefit. The annotation design must preserve durable fallback information in Org: at minimum citekey, page, and quoted/selected text. Package-specific coordinates or annotation IDs may supplement, but not replace, that state.

The initial literature-note structure must not assume a future annotation package's property format.

## Portability and bootstrap

The portable core is Git-backed text:

```text
references.bib
org-roam/
Emacs configuration
```

PDF synchronization is explicitly outside the reference architecture. Syncthing, rsync, Nextcloud, WebDAV, external drives, or another mechanism may provide `~/papers/`; Emacs only depends on the configured attachment root.

A fresh machine with the dotfiles and Org/reference repository but no PDFs must still support:

- bibliography search;
- citation insertion;
- literature-note navigation;
- project/reference relationships;
- normal Org-roam use.

Reference features should degrade independently:

- missing bibliography -> create an empty one on first capture, not at startup;
- missing PDF root -> create it on first attachment operation;
- missing PDF -> report unavailable and continue;
- unavailable network -> local library/citation functions continue and URL/BibTeX capture remains possible;
- unavailable Org-roam -> bibliography and citation functions continue, literature-note action reports the missing capability;
- unavailable optional PDF support -> bibliography and citation functions continue.

The bibliography subsystem must not make normal Emacs startup fail merely because reference resources are absent.

## Emacs module boundary

The subsystem justifies separate declarative and behavior owners.

### `lisp/p3-config-reference.el`

Own declarative/package wiring:

- path/config variables;
- Citar package configuration;
- Org-cite processor configuration;
- Biblio setup;
- pdf-tools setup;
- `C-c b` prefix exposure;
- exact-source load of `p3-reference.el` before wiring its commands.

### `lisp/p3-reference.el`

Own reusable workflow behavior:

- capture/import orchestration;
- duplicate checks;
- enrichment orchestration;
- reference lookup/action helpers;
- citekey finalization guards;
- literature-note lookup/creation;
- project association/removal;
- project-reference retrieval;
- attachment-path resolution/opening.

The behavior layer should use established package APIs for bibliography parsing, completion, Org-roam access, and metadata retrieval. It must not become a private bibliography database or remote metadata implementation.

## Existing citation configuration

The current BibTeX/RefTeX/Citar block is treated as abandoned experimental configuration, not behavior that must be preserved.

The implementation should remove obsolete or overlapping citation machinery unless a current user-facing behavior is identified and intentionally carried forward.

Initial exclusions include:

- Zotero and Better BibTeX;
- RefTeX as the citation-management layer;
- org-ref;
- org-roam-bibtex;
- citar-org-roam;
- Ebib;
- helm-bibtex/ivy-bibtex;
- custom database formats;
- custom browser scraping;
- built-in PDF synchronization.

These are not permanently forbidden. They may be introduced later only to solve an observed problem that the simpler architecture does not handle well.

## Integrity invariants

1. `references.bib` must remain valid BibLaTeX after every successful mutation.
2. Library mutations write and validate a temporary result before atomically replacing the original file; failed validation leaves the original untouched.
3. Mature citekeys are unique and effectively immutable.
4. Provisional records cannot be cited, linked to literature notes, associated with projects, or assigned citekey-based attachment paths until finalized.
5. Enrichment may fill missing metadata automatically but may not silently overwrite populated conflicting data.
6. DOI and normalized-URL equality may identify strong duplicates; title similarity may only warn.
7. Project associations are represented only by unique citekeys in the canonical `* References` subtree of project notes; narrative citations elsewhere do not implicitly modify that registry.
8. Optional package state is never required to reconstruct citation identity, literature-note links, or project associations.
9. Missing PDFs do not invalidate references or notes.
10. Network failure does not block local retrieval or basic capture.
11. Package-specific PDF annotation state must remain supplemental to durable Org text.

## Testing strategy

The subsystem modifies durable personal data, so tests must emphasize data preservation and reconstructability rather than only package loading.

Focused automated coverage should include:

- safe creation of an empty bibliography;
- valid BibLaTeX import;
- malformed import rejected without modifying the library;
- URL-only capture creates an inbox record;
- DOI duplicate detection;
- normalized-URL duplicate detection;
- similar-title warning without automatic merge;
- enrichment fills missing fields without overwriting populated fields;
- finalization presents a deterministic proposed citekey and accepts an explicit user choice;
- finalized citekey cannot change as an incidental enrichment side effect;
- provisional record cannot be cited, linked, project-associated, or attached before finalization;
- citation insertion emits native Org citation syntax;
- literature-note creation writes the correct `ROAM_REFS`;
- repeated note creation opens the existing note;
- project association creates/uses the canonical `* References` subtree and is idempotent;
- narrative citations outside that subtree do not become project associations;
- project-reference retrieval resolves the intended bibliography subset;
- attachment lookup follows the citekey directory convention;
- missing PDF root/PDF/network/optional packages degrade without corrupting state;
- configuration loads without requiring the user's bibliography or PDFs to exist at startup.

A durable architecture regression should prove that, given only `references.bib` and the Org corpus, reference identity, citations, literature-note relationships, and project associations remain reconstructable without Citar, Biblio, pdf-tools, or `p3-reference` private state.

## Implementation scope for v1

V1 includes:

- canonical BibLaTeX bibliography configuration;
- `p3-config-reference.el` and `p3-reference.el`;
- Citar-based retrieval/actions;
- native Org-cite insertion;
- Biblio-backed acquisition/enrichment where practical;
- URL/BibLaTeX capture that survives network failure;
- explicit citekey finalization before durable relationships are created;
- literature-note creation/opening through Org-roam;
- project association and project-scoped retrieval through canonical Org project-note reference subtrees;
- citekey-based PDF directory convention;
- pdf-tools reading integration;
- focused regression tests and existing architecture/CI integration.

V1 explicitly defers:

- browser extension/integration;
- Google Scholar scraping;
- automatic PDF acquisition;
- PDF synchronization;
- precise PDF-to-Org annotation synchronization;
- org-noter/org-pdftools adoption;
- external reference-manager integration;
- a custom standalone bibliography database UI.

## Success criterion

The subsystem succeeds only if ordinary reference work becomes simpler than the current workflow while the durable corpus remains understandable without the subsystem.

A user should be able to capture a source, find it later, connect it to a project or literature note, open its PDF, and cite it in an Org document without remembering which underlying package performs each operation.
