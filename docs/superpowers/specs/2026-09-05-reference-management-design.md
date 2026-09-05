# Emacs-owned reference management design

## Purpose

Build a citation and bibliography workflow that acts as part of the Emacs/Org second brain rather than as a thin front end to an external reference manager.

The durable knowledge model must remain portable and bootstrappable from ordinary files. Packages may provide acquisition, search, citation, note, and PDF-reading interfaces, but no package-specific database may become authoritative.

The system must make common reference operations easier than the current ad hoc BibTeX/RefTeX/Citar configuration. If an added package does not create a distinct ergonomic capability, it should not remain in the design.

## Design goals

The system must support these common workflows:

1. Save an interesting publication when only a URL, DOI, title/search result, pasted formatted citation, or complete BibTeX/BibLaTeX record is available.
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

These keywords are descriptive metadata. They do not determine whether a record is technically provisional or mature.

Project membership is deliberately not stored as bibliography metadata.

### Provisional records and citekeys

A record is technically provisional if and only if its citekey uses the reserved prefix:

```text
p3-inbox-
```

For example:

```text
p3-inbox-20260905-140501
```

This reserved prefix is the sole machine-readable provisional-state contract. A `status/inbox` keyword may also be present for human workflow purposes, but commands must not use that keyword to decide whether a record is provisional.

A provisional record cannot be cited, receive a literature note, be associated with a project, or receive a citekey-based PDF attachment directory.

Finalization proposes a deterministic permanent citekey from mature bibliographic metadata. The proposed key is shown to the user before acceptance and may be edited at that point. The exact author/year/title formatting convention is configuration, not corpus structure.

After finalization, the citekey is immutable within v1. The v1 reference workflow does not provide mature-citekey renaming or migration. If that need arises later, it requires a separately designed migration operation because the key may already appear in Org citations, `ROAM_REFS`, project reference registries, and PDF paths.

The mature citekey is the stable join across the system:

```text
BibLaTeX        @fellegi1969
Org citation    [cite:@fellegi1969]
Literature note :ROAM_REFS: @fellegi1969
PDF directory   ~/papers/fellegi1969/
```

### PDFs

PDFs remain outside Git and outside the bibliography's consistency model.

Use a configurable attachment root and a deterministic mature-citekey layout:

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

A machine-readable `project` Org-roam tag identifies project notes. Each project note uses one top-level `* References` subtree as the canonical explicit association registry:

```org
#+title: SAIDS
#+filetags: :project:

* References

[cite:@fellegi1969]
[cite:@smith2024]
```

The reference workflow creates the `* References` subtree when necessary and keeps associations unique. `C-c b r` reads this subtree rather than treating every narrative citation elsewhere in the project note as an automatic project association.

The registry intentionally uses real native Org citations. Org and Org-roam may therefore index these entries as citations and expose their citation backlinks. That behavior is part of the design, not an implementation accident.

Ordinary narrative citations elsewhere in the project note remain semantically distinct from the explicit project-reference registry.

One reference may therefore relate to zero, one, or many projects without duplicating or modifying the bibliographic record.

If the current note is not unambiguously a project, project-aware commands prompt rather than guessing.

Project association and literature-note creation remain independent. A project may associate a reference that has no literature note.

## User-facing workflow contract

Expose one stable reference prefix, initially `C-c b`. Package-specific commands should remain implementation details.

This intentionally replaces the current Org-local `C-c b` binding that directly invokes `org-cite-insert`. Citation insertion moves to `C-c b i`. Tests should pin this transition so it is not an incidental side effect of deleting the old citation block.

### `C-c b a` — add reference

Accept the material the user already has rather than forcing a capture mode first.

Recognize these inputs:

- DOI -> metadata lookup;
- BibTeX/BibLaTeX -> normalize and import;
- URL -> extract/use a DOI when one is directly recognizable; otherwise save immediately as a provisional URL-only record;
- ordinary title/author text -> bibliographic search;
- pasted formatted citation text -> treat as bibliographic search input and present structured matches; do not parse arbitrary citation styles into records directly.

Capture follows **save first, enrich second**. Network or metadata lookup failure must not prevent saving a URL-only provisional record.

Google Scholar is treated as an import source, not as a scraped dependency. The supported low-friction path is Scholar's BibTeX export copied into `C-c b a`; a copied formatted Scholar citation may instead be used as search input.

### `C-c b f` — find reference

Fuzzy-search the complete library by useful bibliographic fields and keywords. An empty query must allow browsing the full library, so v1 does not need a separate library command.

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

If the selected record is provisional, citation insertion first enters the explicit finalization flow.

### `C-c b n` — literature note

Select a reference or use the reference at point.

- If the selected record is provisional, finalize it first.
- If a literature note with the corresponding `ROAM_REFS` already exists, open it.
- Otherwise create exactly one minimal Org-roam literature note and place point in the body.

Repeated invocation must not create duplicate literature notes.

### `C-c b p` — open PDF

Resolve the selected mature citekey to its attachment directory and open `main.pdf` when present.

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

## Capture and enrichment

Use `biblio.el` where it provides stable bibliographic search/lookup functionality, especially DOI/title lookup through sources such as Crossref. Do not reimplement remote metadata protocols in `p3-reference.el`.

V1 does not implement a generic webpage metadata scraper or site-specific URL enrichment engine. URL capture may use a DOI directly recognizable in the URL or supplied metadata; otherwise the URL is saved immediately as a provisional record. Later enrichment proceeds through DOI or title search.

Enrichment may run opportunistically during capture and explicitly later.

Preferred lookup order for an incomplete record:

1. DOI when present;
2. title/author search;
3. manual editing.

Enrichment may fill blank fields automatically. It must not silently overwrite populated user data when the retrieved value differs materially.

### Duplicate handling

Before adding a mature record:

1. exact normalized DOI match is a strong duplicate;
2. exact normalized URL match is a strong duplicate;
3. title similarity is only a warning and never an automatic merge.

Strong duplicates should lead to the existing record rather than add a second copy.

The design prefers a visible possible duplicate over an incorrect automatic merge.

## Bibliography mutation and validation

The workflow modifies a durable Git-friendly text file, so mutations must preserve unrelated bibliography text where practical.

Library-writing commands should perform targeted entry-level edits or append/import operations rather than parse and reserialize the entire bibliography on every mutation. Unrelated entries, comments, ordering, and formatting should remain byte-for-byte unchanged where the underlying operation permits it.

Before committing a mutation to `references.bib`:

1. write the candidate result to a temporary file in the same filesystem;
2. parse it using established BibTeX/BibLaTeX support sufficient to detect syntactic invalidity;
3. verify citekey uniqueness;
4. only then replace the original file atomically.

If validation fails, leave the original bibliography untouched and retain no hidden package state as an alternative source of truth.

V1 does not attempt to implement a complete semantic BibLaTeX validator.

## PDF reading and annotations

`pdf-tools` belongs in the initial subsystem because the intended workflow includes reading stored papers in Emacs and opening them from reference actions.

PDF support is optional at runtime. The reference subsystem must not eagerly require or initialize `pdf-tools` in a way that makes startup or bibliography/citation functions fail when its native backend is unavailable. PDF support should load lazily when a PDF action is invoked or when a PDF buffer is opened; missing native support is reported locally to that action.

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
- unavailable or broken PDF support -> bibliography and citation functions continue.

The bibliography subsystem must not make normal Emacs startup fail merely because reference resources are absent.

## Emacs module boundary

The subsystem justifies separate declarative and behavior owners.

### `lisp/p3-config-reference.el`

Own declarative/package wiring:

- path/config variables;
- Citar package configuration;
- Org-cite processor configuration;
- Biblio setup;
- lazy/non-fatal pdf-tools setup;
- `C-c b` prefix exposure;
- exact-source load of `p3-reference.el` before wiring its commands.

### `lisp/p3-reference.el`

Own reusable workflow behavior:

- capture/import orchestration;
- provisional-key generation and finalization guards;
- duplicate checks;
- enrichment orchestration;
- targeted bibliography mutations and validation orchestration;
- reference lookup/action helpers;
- literature-note lookup/creation;
- project association/removal;
- project-reference retrieval;
- attachment-path resolution/opening.

The behavior layer should use established package APIs for bibliography parsing, completion, Org-roam access, and metadata retrieval. It must not become a private bibliography database, generic webpage scraper, or remote metadata implementation.

## Existing citation configuration

The current BibTeX/RefTeX/Citar block is treated as abandoned experimental configuration, not behavior that must be preserved.

The implementation should remove obsolete or overlapping citation machinery unless a current user-facing behavior is identified and intentionally carried forward.

The current Org-local `C-c b` -> `org-cite-insert` binding is intentionally retired in favor of the reference prefix; native citation insertion remains available through `C-c b i` and Org's own standard citation commands.

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
- mature-citekey migration machinery;
- built-in PDF synchronization.

These are not permanently forbidden. They may be introduced later only to solve an observed problem that the simpler architecture does not handle well.

## Integrity invariants

1. `references.bib` must remain valid BibLaTeX after every successful mutation.
2. Library mutations preserve unrelated bibliography text where practical, validate a temporary candidate, verify unique citekeys, and atomically replace the original only after validation succeeds.
3. A citekey beginning with `p3-inbox-` is provisional; no other field determines provisional state.
4. Mature citekeys are unique and immutable in v1; mature-key rename/migration is unsupported.
5. Provisional records cannot be cited, linked to literature notes, associated with projects, or assigned citekey-based attachment paths until finalized.
6. Enrichment may fill missing metadata automatically but may not silently overwrite populated conflicting data.
7. DOI and normalized-URL equality may identify strong duplicates; title similarity may only warn.
8. Project associations are represented only by unique native Org citations in the canonical `* References` subtree of project notes; narrative citations elsewhere do not implicitly modify that registry.
9. Citation indexing/backlinks produced by the project registry are intentional.
10. Optional package state is never required to reconstruct citation identity, literature-note links, or project associations.
11. Missing PDFs do not invalidate references or notes.
12. Network failure does not block local retrieval or basic capture.
13. Package-specific PDF annotation state must remain supplemental to durable Org text.

## Testing strategy

The subsystem modifies durable personal data, so tests must emphasize data preservation and reconstructability rather than only package loading.

Focused automated coverage should include:

- safe creation of an empty bibliography;
- valid BibLaTeX import;
- malformed import rejected without modifying the library;
- targeted mutation preserves unrelated bibliography text;
- duplicate citekeys are rejected before atomic replacement;
- URL-only capture creates a `p3-inbox-*` provisional record;
- `status/inbox` alone does not make a mature citekey provisional;
- DOI duplicate detection;
- normalized-URL duplicate detection;
- similar-title warning without automatic merge;
- formatted citation text is treated as search input rather than parsed directly;
- generic URL capture does not depend on webpage scraping;
- enrichment fills missing fields without overwriting populated fields;
- finalization presents a deterministic proposed citekey and accepts an explicit user choice;
- finalized citekey cannot change as an incidental enrichment side effect;
- mature citekey rename is not exposed by the v1 workflow;
- provisional record cannot be cited, linked, project-associated, or attached before finalization;
- citation insertion emits native Org citation syntax;
- `C-c b` is the reference prefix and `C-c b i` performs citation insertion;
- literature-note creation writes the correct `ROAM_REFS`;
- repeated note creation opens the existing note;
- project association creates/uses the canonical `* References` subtree and is idempotent;
- project-registry citations are ordinary Org citations and remain indexable;
- narrative citations outside that subtree do not become project associations;
- project-reference retrieval resolves the intended bibliography subset;
- attachment lookup follows the mature-citekey directory convention;
- missing PDF root/PDF/network/Org-roam degrade without corrupting state;
- missing or unusable pdf-tools backend does not prevent reference configuration or citation functions from loading;
- configuration loads without requiring the user's bibliography or PDFs to exist at startup.

A durable architecture regression should prove that, given only `references.bib` and the Org corpus, reference identity, citations, literature-note relationships, and project associations remain reconstructable without Citar, Biblio, pdf-tools, or `p3-reference` private state.

## Implementation scope for v1

V1 includes:

- canonical BibLaTeX bibliography configuration;
- `p3-config-reference.el` and `p3-reference.el`;
- Citar-based retrieval/actions;
- native Org-cite insertion;
- Biblio-backed DOI/title acquisition and enrichment where practical;
- URL/BibLaTeX capture that survives network failure;
- formatted-citation-to-search workflow;
- explicit provisional-key contract and citekey finalization before durable relationships are created;
- targeted, validated, atomic bibliography mutations;
- literature-note creation/opening through Org-roam;
- project association and project-scoped retrieval through canonical Org project-note reference subtrees;
- citekey-based PDF directory convention;
- lazy/non-fatal pdf-tools reading integration;
- focused regression tests and existing architecture/CI integration.

V1 explicitly defers:

- browser extension/integration;
- Google Scholar scraping;
- generic webpage metadata scraping;
- automatic PDF acquisition;
- PDF synchronization;
- precise PDF-to-Org annotation synchronization;
- org-noter/org-pdftools adoption;
- external reference-manager integration;
- mature-citekey migration/rename tooling;
- a custom standalone bibliography database UI.

## Success criterion

The subsystem succeeds only if ordinary reference work becomes simpler than the current workflow while the durable corpus remains understandable without the subsystem.

A user should be able to capture a source, find it later, connect it to a project or literature note, open its PDF, and cite it in an Org document without remembering which underlying package performs each operation.
