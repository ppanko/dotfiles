# Emacs Reference Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an Emacs-owned, plain-file reference workflow that safely captures, retrieves, cites, classifies, project-associates, notes, and opens publications without making any package-specific database authoritative.

**Architecture:** `references.bib` is the canonical BibLaTeX database; Org files are the canonical literature-note and project-association graph; PDFs are optional files under a configurable citekey-based root. `p3-reference.el` owns the stable workflow and data-safety rules, while `p3-config-reference.el` owns Citar, Biblio, Org-cite, pdf-tools, paths, and the `C-c b` prefix. Citar supplies bibliographic selection, Biblio supplies DOI/Crossref acquisition, Org-roam supplies note/project nodes, and pdf-tools is a lazy reader; all durable relationships remain reconstructable from BibLaTeX and Org alone.

**Tech Stack:** Emacs 29+ Lisp, built-in `bibtex`, Org/Org-cite, Org-roam, Citar, Biblio.el, optional/lazy pdf-tools, ERT, existing literate config loader, GitHub Actions on Ubuntu and Windows.

**Spec:** `docs/superpowers/specs/2026-09-05-reference-management-design.md`

## Global Constraints

- `references.bib` and Org files are authoritative; no private package cache or database may become required state.
- A citekey beginning with `p3-inbox-` is provisional; no keyword or other field may substitute for this test.
- Provisional records cannot be cited, linked to a literature note, associated with a project, or assigned a citekey-based attachment path until finalized.
- Mature citekeys are unique and immutable in v1; do not add mature-key migration/rename machinery.
- Bibliography mutations must preserve unrelated text where practical, validate a same-filesystem temporary candidate, verify unique citekeys, and atomically replace the original only after validation succeeds.
- Enrichment may fill blank fields but must not silently overwrite populated conflicting fields.
- DOI and normalized-URL equality are strong duplicate signals; normalized-title similarity only warns and never auto-merges.
- URL capture may recognize a DOI but must not grow into generic webpage scraping or site-specific metadata extraction.
- Project associations live only as unique native Org citations under one top-level `* References` subtree in a `:project:` Org-roam note; narrative citations elsewhere do not become associations.
- Citation indexing/backlinks caused by those registry citations are intentional.
- The reference subsystem must load without the user's bibliography, PDFs, Org-roam availability, or a working pdf-tools native backend.
- pdf-tools is lazy/non-fatal; do not make its native backend a startup prerequisite and do not add Windows-specific PDF setup to this PR.
- The current Org-local `C-c b -> org-cite-insert` binding is intentionally replaced by the reference prefix; citation insertion moves to `C-c b i`.
- Do not preserve the abandoned RefTeX/citar-org-roam experiment merely for compatibility.
- Do not add Zotero, Better BibTeX, org-ref, org-roam-bibtex, citar-org-roam, Ebib, helm-bibtex/ivy-bibtex, browser scraping, PDF synchronization, org-noter, or org-pdftools in v1.
- Keep GitHub Actions bounded: use focused local/batch tests throughout; push one coherent implementation for CI, and use CI diagnostically only if local evidence cannot resolve a platform/package boundary.
- Do not merge without explicit user approval.

---

## File Map

**Create**

- `lisp/p3-reference.el` — durable reference workflow, safe BibLaTeX mutation, capture/finalization, retrieval actions, Org-roam/project integration, and attachment resolution.
- `lisp/p3-config-reference.el` — paths, package declarations, Org-cite/Citar/Biblio/pdf-tools wiring, and global `C-c b` binding.
- `test/p3-reference-test.el` — behavior/data-integrity tests using temporary bibliographies, Org directories, and package API stubs.
- `test/p3-config-reference-test.el` — declarative ownership, package wiring, command-map, and lazy-PDF boundary tests.

**Modify**

- `config.org` — replace the abandoned inline BibTeX/RefTeX/Citar block with one `p3-config-reference` orchestration call.
- `lisp/p3-config-org-roam.el` — remove the old citar-org-roam-dependent literature capture template; ordinary Org-roam capture remains unchanged.
- `test/p3-config-org-roam-test.el` — pin removal of the old citation-specific capture template while preserving normal Org-roam configuration.
- `lisp/p3-config-base.el` — add Which-Key labels for the reference prefix/actions.
- `lisp/p3-commands.el` — replace the old Org `C-c b` atlas entry with a dedicated References section.
- `test/p3-config-test.el` — raise config-owner count to 14, pin reference-owner placement, forbid old inline citation machinery, and pin keybinding-atlas ownership.
- `.github/workflows/emacs-tests.yml` — compile/smoke/test the new reference boundary on Ubuntu.
- `.github/workflows/windows-platform-tests.yml` — include reference files/tests in path filtering and architecture tests without exercising pdf-tools native behavior.

---

### Task 1: Safe bibliography core and provisional-state contract

**Files:**
- Create: `lisp/p3-reference.el`
- Create: `test/p3-reference-test.el`

**Interfaces:**
- Consumes: built-in `bibtex`; dynamically bound `p3/reference-bibliography-file`.
- Produces:
  - `p3/reference-provisional-key-p (citekey) -> boolean`
  - `p3/reference--new-provisional-key () -> string`
  - `p3/reference--bibliography-path () -> absolute path or user-error`
  - `p3/reference--entry-keys (content) -> list[string]`
  - `p3/reference--validate-content (content) -> t or signal`
  - `p3/reference--transaction (edit-fn) -> result`, where `edit-fn` mutates a temporary BibTeX buffer and the transaction commits only a valid unique-key result
  - `p3/reference--goto-entry (citekey) -> non-nil or nil`
  - `p3/reference--entry-alist (citekey) -> bibtex-parse-entry alist or nil`

- [ ] **Step 1: Write failing tests for the provisional key contract and absent-library bootstrap behavior**

Add tests that bind a temporary `p3/reference-bibliography-file` and assert:

```elisp
(ert-deftest p3-reference-provisional-state-is-key-prefix-only ()
  (should (p3/reference-provisional-key-p "p3-inbox-20260905-140501"))
  (should-not (p3/reference-provisional-key-p "smith2026"))
  (should-not (p3/reference-provisional-key-p nil)))

(ert-deftest p3-reference-new-provisional-keys-are-reserved-and-distinct ()
  (let ((first (p3/reference--new-provisional-key))
        (second (p3/reference--new-provisional-key)))
    (should (string-prefix-p "p3-inbox-" first))
    (should (string-prefix-p "p3-inbox-" second))
    (should-not (equal first second))))

(ert-deftest p3-reference-missing-bibliography-is-not-created-by-load ()
  (let* ((dir (make-temp-file "p3-reference-" t))
         (p3/reference-bibliography-file (expand-file-name "references.bib" dir)))
    (unwind-protect
        (progn
          (should-not (file-exists-p p3/reference-bibliography-file))
          (should (featurep 'p3-reference))
          (should-not (file-exists-p p3/reference-bibliography-file)))
      (delete-directory dir t))))
```

- [ ] **Step 2: Run the focused tests and verify they fail for missing implementation**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-reference-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: FAIL because `p3-reference.el` and the provisional helpers do not exist yet.

- [ ] **Step 3: Add the minimal load-safe core and reserved-key generator**

Start `lisp/p3-reference.el` with only built-in dependencies and declarations for configuration-owned variables:

```elisp
;;; p3-reference.el --- Portable reference workflow -*- lexical-binding: t; -*-

(require 'bibtex)
(require 'cl-lib)
(require 'subr-x)

(defvar p3/reference-bibliography-file nil)
(defvar p3/reference-pdf-directory nil)

(defconst p3/reference-provisional-prefix "p3-inbox-")
(defvar p3/reference--provisional-sequence 0)

(defun p3/reference-provisional-key-p (citekey)
  (and (stringp citekey)
       (string-prefix-p p3/reference-provisional-prefix citekey)))

(defun p3/reference--new-provisional-key ()
  (setq p3/reference--provisional-sequence
        (1+ p3/reference--provisional-sequence))
  (format "%s%s-%03d"
          p3/reference-provisional-prefix
          (format-time-string "%Y%m%d-%H%M%S")
          p3/reference--provisional-sequence))
```

Do not require Citar, Biblio, Org-roam, or pdf-tools at library load time.

- [ ] **Step 4: Add failing tests for syntactic validation, duplicate keys, and targeted preservation**

Use fixture strings such as:

```elisp
(defconst p3-reference-test--two-entries
  "@article{alpha2020,\n  title = {Alpha},\n  doi = {10.1000/alpha}\n}\n\n% keep this comment exactly\n@article{beta2021,\n  title = {Beta}\n}\n")
```

Pin these behaviors:

```elisp
(ert-deftest p3-reference-validation-rejects-duplicate-citekeys () ...)
(ert-deftest p3-reference-validation-rejects-malformed-bibtex () ...)
(ert-deftest p3-reference-transaction-leaves-original-on-failure () ...)
(ert-deftest p3-reference-targeted-transaction-preserves-unrelated-text () ...)
```

The preservation test should mutate only `alpha2020` and assert the exact substring from `% keep this comment exactly` through the complete `beta2021` entry is unchanged.

- [ ] **Step 5: Run the focused tests and verify the new integrity cases fail**

Run the same focused ERT command. Expected: the provisional tests pass; validation/transaction tests fail because those helpers are absent.

- [ ] **Step 6: Implement same-filesystem validated atomic transactions**

Implement the transaction shape explicitly:

```elisp
(defun p3/reference--transaction (edit-fn)
  (let* ((target (p3/reference--bibliography-path))
         (directory (file-name-directory target))
         (original (if (file-exists-p target)
                       (with-temp-buffer
                         (insert-file-contents target)
                         (buffer-string))
                     ""))
         result candidate)
    (make-directory directory t)
    (with-temp-buffer
      (insert original)
      (bibtex-mode)
      (bibtex-set-dialect 'biblatex t)
      (setq result (funcall edit-fn))
      (setq candidate (buffer-string)))
    (p3/reference--validate-content candidate)
    (let ((temp (make-temp-file
                 (expand-file-name ".p3-references-" directory)
                 nil ".bib" candidate)))
      (unwind-protect
          (progn
            (when (file-exists-p target)
              (set-file-modes temp (file-modes target)))
            (rename-file temp target t)
            (setq temp nil))
        (when (and temp (file-exists-p temp))
          (delete-file temp))))
    result))
```

`p3/reference--validate-content` must:

1. parse every ordinary entry with built-in BibTeX support and signal on malformed syntax;
2. collect ordinary-entry citekeys while excluding `@string`, `@preamble`, and `@comment` pseudo-entries;
3. signal when any citekey occurs more than once.

Implement `p3/reference--goto-entry` with a quoted citekey and an anchored BibTeX-entry-header regexp so later operations can mutate only one entry. Do not parse and reserialize the whole bibliography.

- [ ] **Step 7: Run focused tests and verify Task 1 is green**

Run the focused ERT command. Expected: all Task 1 tests PASS and no external package is needed.

- [ ] **Step 8: Commit Task 1**

```bash
git add lisp/p3-reference.el test/p3-reference-test.el
git commit -m "Add safe reference bibliography core"
```

---

### Task 2: Import, duplicate detection, keyword mutation, and citekey finalization

**Files:**
- Modify: `lisp/p3-reference.el`
- Modify: `test/p3-reference-test.el`

**Interfaces:**
- Consumes: Task 1 transaction/entry helpers.
- Produces:
  - `p3/reference-normalize-doi (doi) -> string or nil`
  - `p3/reference-normalize-url (url) -> string or nil`
  - `p3/reference-import-bibtex (bibtex) -> citekey`
  - `p3/reference-finalize (citekey) -> mature citekey`
  - `p3/reference-add-keyword (citekey keyword) -> t`
  - `p3/reference-remove-keyword (citekey keyword) -> t`
  - `p3/reference--strong-duplicate-key (entry-alist) -> citekey or nil`
  - `p3/reference--possible-title-duplicate-keys (entry-alist) -> list[string]`

- [ ] **Step 1: Write failing normalization and duplicate tests**

Pin these examples:

```elisp
(should (equal (p3/reference-normalize-doi "https://doi.org/10.1000/ABC ")
               "10.1000/abc"))
(should (equal (p3/reference-normalize-url "HTTPS://Example.COM/paper/#section")
               "https://example.com/paper"))
```

Create a temporary bibliography and assert:

- importing an entry with an already-present DOI returns/leads to the existing citekey and does not append a duplicate;
- importing an entry with an already-present normalized URL does the same;
- a normalized-title match triggers a confirmation/warning path but is never auto-merged;
- a new unique mature entry appends exactly once;
- a malformed pasted entry leaves the bibliography byte-for-byte unchanged.

For title warnings, use a conservative v1 rule: lowercase, collapse whitespace, remove punctuation, and treat equality after that normalization as a possible duplicate. Do not introduce an arbitrary fuzzy-distance threshold.

- [ ] **Step 2: Run the focused tests and verify they fail**

Expected: failures for normalization/import/duplicate functions only.

- [ ] **Step 3: Implement import and duplicate checks using parsed fields, not package caches**

`p3/reference-import-bibtex` must:

1. require exactly one ordinary BibTeX/BibLaTeX entry in the supplied text;
2. parse its citekey, DOI, URL, and title;
3. reject a `p3-inbox-*` key when the incoming record is already a structured mature import; provisional keys are reserved for URL-only capture;
4. check DOI and normalized URL against the canonical bibliography;
5. warn/confirm on normalized-title duplicates but never merge automatically;
6. append the supplied entry through `p3/reference--transaction`, preserving all existing text;
7. return the canonical citekey actually used.

Do not call Citar to determine duplicates; the answer must be reconstructable from `references.bib` alone.

- [ ] **Step 4: Add failing tests for keyword mutation and mature-key finalization**

Tests must pin:

```elisp
(ert-deftest p3-reference-status-inbox-does-not-make-a-mature-key-provisional () ...)
(ert-deftest p3-reference-keyword-mutation-is-idempotent-and-entry-local () ...)
(ert-deftest p3-reference-finalization-rejects-mature-key-renaming () ...)
(ert-deftest p3-reference-finalization-renames-only-provisional-entry-head () ...)
(ert-deftest p3-reference-finalization-rejects-colliding-proposed-key () ...)
```

For finalization tests, stub `read-string` so the proposed key is deterministic and assert no citation/note/project/PDF migration function exists.

- [ ] **Step 5: Run focused tests and verify the new cases fail**

Expected: import tests remain green; keyword/finalization tests fail.

- [ ] **Step 6: Implement entry-local keyword mutation and finalization**

Use Task 1's transaction plus built-in `bibtex-set-field` for `keywords` inside the selected entry. Parse comma-separated keywords, trim them, de-duplicate them, and preserve all other entries exactly.

For finalization:

```elisp
(defun p3/reference-finalize (citekey)
  (if (not (p3/reference-provisional-key-p citekey))
      citekey
    ;; locate only this provisional entry
    ;; call built-in `bibtex-generate-autokey' in an isolated entry buffer
    ;; present that proposed key via `read-string'
    ;; reject empty, `p3-inbox-*`, or colliding keys
    ;; replace only the entry-head key inside a validated transaction
    ;; return the accepted mature key
    ))
```

Do not expose any command that renames a mature citekey.

- [ ] **Step 7: Run focused tests and verify Task 2 is green**

Run the focused ERT command. Expected: all Task 1–2 tests PASS.

- [ ] **Step 8: Commit Task 2**

```bash
git add lisp/p3-reference.el test/p3-reference-test.el
git commit -m "Add reference import and finalization"
```

---

### Task 3: DOI, URL, BibTeX, and bibliographic-search capture

**Files:**
- Modify: `lisp/p3-reference.el`
- Modify: `test/p3-reference-test.el`

**Interfaces:**
- Consumes: Task 2 safe import/finalization functions; Biblio APIs loaded only when acquisition is invoked.
- Produces:
  - `p3/reference-add (&optional input) -> immediate citekey for local paths, or starts Biblio async lookup`
  - `p3/reference--input-kind (input) -> one of 'bibtex 'doi 'url 'search`
  - `p3/reference--doi-in-string (string) -> normalized DOI or nil`
  - `p3/reference--capture-url (url) -> provisional citekey`
  - `p3/reference-biblio-save (metadata) -> async save through the result backend`
  - `p3/reference-enrich (citekey) -> explicit enrichment flow`

- [ ] **Step 1: Write failing input-routing and URL-capture tests**

Pin routing behavior:

```elisp
(should (eq (p3/reference--input-kind "@article{x, title={X}}") 'bibtex))
(should (eq (p3/reference--input-kind "10.1000/xyz") 'doi))
(should (eq (p3/reference--input-kind "https://example.org/article") 'url))
(should (eq (p3/reference--input-kind "Smith measurement error 2024") 'search))
```

Also assert:

- a DOI embedded in `https://doi.org/...` routes to DOI acquisition rather than provisional URL capture;
- an ordinary URL without a directly recognizable DOI produces an `@online{p3-inbox-..., ...}` entry containing the URL, current `urldate`, and `status/inbox`;
- URL capture works with all Biblio functions deliberately unbound/stubbed to error, proving no webpage scraper dependency;
- pasted formatted citation text routes to search, not direct citation-style parsing.

- [ ] **Step 2: Run focused tests and verify they fail**

Expected: failures for capture routing and URL creation.

- [ ] **Step 3: Implement local capture paths first**

`p3/reference-add` should prompt once when INPUT is nil and dispatch as follows:

```elisp
(pcase (p3/reference--input-kind input)
  ('bibtex (p3/reference-import-bibtex input))
  ('doi    (p3/reference--lookup-doi input))
  ('url    (p3/reference--capture-url input))
  ('search (p3/reference--lookup-title input)))
```

`p3/reference--capture-url` must call the validated transaction and append only the provisional `@online` entry. It may not fetch the URL.

- [ ] **Step 4: Add failing Biblio integration tests with package functions stubbed**

Stub these established APIs rather than performing network calls:

- `biblio-doi-forward-bibtex (doi callback)`;
- `biblio-format-bibtex (bibtex autokey)`;
- `biblio-crossref-lookup (query)`;
- the Biblio result metadata `backend` protocol command `forward-bibtex`.

Assert:

- DOI lookup formats the returned BibTeX and feeds it through `p3/reference-import-bibtex`;
- title/formatted-citation search invokes Crossref with the original search text;
- `p3/reference-biblio-save` asks the result's backend for BibTeX and sends the formatted result through the safe importer;
- Biblio/network failure leaves an existing bibliography unchanged;
- enrichment of a provisional item fills blank data only, and conflicting populated fields require explicit user choice before replacement.

- [ ] **Step 5: Run focused tests and verify the Biblio cases fail**

Expected: local capture tests pass; Biblio integration tests fail.

- [ ] **Step 6: Implement lazy Biblio acquisition through public extension points**

Use `require ... nil t` only inside acquisition functions. For DOI:

```elisp
(unless (require 'biblio-doi nil t)
  (user-error "Biblio DOI support is unavailable"))
(biblio-doi-forward-bibtex
 normalized-doi
 (lambda (bibtex)
   (p3/reference-import-bibtex
    (biblio-format-bibtex bibtex nil))))
```

For search, call `biblio-crossref-lookup` with the query. Implement `p3/reference-biblio-save` against Biblio's documented result metadata backend protocol:

```elisp
(let ((backend (alist-get 'backend metadata)))
  (funcall backend 'forward-bibtex metadata
           (lambda (bibtex)
             (p3/reference-import-bibtex
              (biblio-format-bibtex bibtex nil)))))
```

Do not call Biblio's private selection-buffer insertion functions.

`p3/reference-enrich` may use DOI lookup when the provisional record already contains a DOI; otherwise launch a Crossref search using its best available title/URL text and reuse `p3/reference-biblio-save`. Keep it an `M-x` command in v1; do not add an unapproved prefix key merely to expose it.

- [ ] **Step 7: Run focused tests and verify Task 3 is green**

Expected: all behavior tests PASS without network access.

- [ ] **Step 8: Commit Task 3**

```bash
git add lisp/p3-reference.el test/p3-reference-test.el
git commit -m "Add reference acquisition workflow"
```

---

### Task 4: Citar-backed retrieval, action dispatch, and Org-cite insertion

**Files:**
- Modify: `lisp/p3-reference.el`
- Modify: `test/p3-reference-test.el`

**Interfaces:**
- Consumes: Task 2 finalization; Citar public APIs loaded only by retrieval/citation commands.
- Produces:
  - `p3/reference--select-key (&optional allowed-keys) -> citekey or nil`
  - `p3/reference-find (&optional allowed-keys) -> dispatch one action for selected citekey`
  - `p3/reference-insert-citation (&optional citekey) -> inserts native Org citation through Citar`
  - `p3/reference-open-url (&optional citekey) -> browse URL/DOI URL`
  - `p3/reference-edit-entry (&optional citekey) -> visit canonical BibLaTeX entry`
  - `p3/reference--action-alist () -> stable action label/function pairs`

- [ ] **Step 1: Write failing Citar selection/action tests using stubs**

Do not load a real Citar cache. Stub:

- `citar-select-ref` and inspect its `:filter` argument;
- `citar-get-value`;
- `citar-open-entry-in-file`;
- `browse-url`.

Assert that:

- an unrestricted find uses the entire Citar library;
- a project-filtered find permits only the supplied citekeys;
- an empty allowed-key list reports that the project has no associated references rather than searching globally;
- the action menu can dispatch `Open URL` and `Edit bibliography entry` for the selected key;
- URL opening falls back to `https://doi.org/<doi>` only when `url` is absent.

- [ ] **Step 2: Run focused tests and verify they fail**

Expected: Citar wrapper tests fail; acquisition/storage tests remain green.

- [ ] **Step 3: Implement the thin Citar selection/action adapter**

Use Citar only to select bibliography keys and retrieve fields. The P3 action menu remains the stable workflow surface:

```elisp
(defun p3/reference-find (&optional allowed-keys)
  (interactive)
  (let ((key (p3/reference--select-key allowed-keys)))
    (when key
      (let* ((actions (p3/reference--action-alist))
             (label (completing-read "Reference action: " actions nil t))
             (fn (cdr (assoc label actions))))
        (funcall fn key)))))
```

This avoids adding a separate Embark/Citar integration package solely to compose actions.

- [ ] **Step 4: Add failing citation-finalization tests**

Assert:

- mature key -> `citar-insert-citation` receives that exact key;
- provisional key -> `p3/reference-finalize` runs first, and Citar receives only the mature result;
- output is native Org citation behavior supplied by Citar/Org-cite, with no package-specific citation text inserted by P3;
- a mature `status/inbox` record is not finalized because status metadata does not define technical provisionality.

- [ ] **Step 5: Run focused tests and verify citation cases fail**

Expected: selection/action tests pass; citation wrapper cases fail.

- [ ] **Step 6: Implement citation and basic reference actions**

`p3/reference-insert-citation` should:

1. select a key when none is supplied;
2. finalize only `p3-inbox-*` keys;
3. call `citar-insert-citation` with the final key list.

Do not construct `[cite:@...]` strings manually in the interactive command; Org/Citar remains responsible for citation syntax.

- [ ] **Step 7: Run focused tests and verify Task 4 is green**

Expected: all Task 1–4 behavior tests PASS.

- [ ] **Step 8: Commit Task 4**

```bash
git add lisp/p3-reference.el test/p3-reference-test.el
git commit -m "Add reference retrieval and citation actions"
```

---

### Task 5: Org-roam literature notes and canonical project-reference registries

**Files:**
- Modify: `lisp/p3-reference.el`
- Modify: `test/p3-reference-test.el`

**Interfaces:**
- Consumes: mature citekeys and Task 4 selection/action interface; Org-roam APIs only when note/project commands run.
- Produces:
  - `p3/reference-note (&optional citekey) -> visits/creates one literature note`
  - `p3/reference--literature-note-path (citekey) -> path`
  - `p3/reference--current-project-node () -> node or nil`
  - `p3/reference--select-project-node () -> project-tagged node`
  - `p3/reference-associate-project (citekey &optional node) -> t`
  - `p3/reference-remove-project-association (citekey &optional node) -> t`
  - `p3/reference-project-citekeys (&optional node) -> list[string]`
  - `p3/reference-project-references (&optional node) -> same Citar action UI restricted to project keys`
  - `p3/reference-classify (&optional citekey) -> topic/status/project action dispatcher`

- [ ] **Step 1: Write failing literature-note tests with a temporary Org-roam directory**

Stub `org-roam-node-from-ref`, `org-roam-node-visit`, `org-id-new`, and the Citar field getter as needed. Assert:

- a provisional key is finalized before any note path is created;
- an existing `ROAM_REFS: @key` node is visited rather than duplicated;
- a new note contains exactly one durable reference property, a generated Org ID, a `:literature:` file tag, and a human-readable title derived from the bibliography;
- invoking note creation twice yields one file/node;
- creating a note does not copy DOI/URL/author/year fields wholesale into the Org file.

The minimal new-note header should be structurally equivalent to:

```org
:PROPERTIES:
:ID: <org-id>
:ROAM_REFS: @fellegi1969
:END:
#+title: Fellegi & Sunter — A Theory for Record Linkage
#+filetags: :literature:

```

- [ ] **Step 2: Run focused tests and verify note tests fail**

Expected: Task 1–4 tests pass; note tests fail.

- [ ] **Step 3: Implement literature-note lookup/creation without citar-org-roam**

Use `org-roam-node-from-ref` with `@<citekey>` to locate existing reference notes. For new notes, use a deterministic mature-citekey filename under `org-roam-directory`, create the plain Org header, save it, and allow normal Org-roam autosync to index it. Do not recreate the old `citar-org-roam` capture template or depend on its variables.

- [ ] **Step 4: Add failing project-registry tests**

Use temporary Org files with both narrative citations and a canonical top-level subtree:

```org
#+title: Example
#+filetags: :project:

A narrative mention [cite:@narrative2020] belongs to prose.

* References

[cite:@alpha2020]
```

Assert:

- `p3/reference-project-citekeys` returns only `alpha2020`;
- adding `beta2021` creates one new registry line and is idempotent;
- adding a first reference creates a top-level `* References` subtree when absent;
- removing `alpha2020` removes only its registry line, not narrative citations elsewhere;
- project association finalizes a provisional key first;
- only nodes tagged `project` are accepted as project targets;
- the stored registry entries remain ordinary `[cite:@key]` syntax;
- `p3/reference-project-references` calls the same Task 4 find/action path with exactly the registry citekeys.

- [ ] **Step 5: Run focused tests and verify project tests fail**

Expected: literature-note tests pass; project registry tests fail.

- [ ] **Step 6: Implement project registry parsing and mutation with Org's syntax tree**

Use Org parsing to find a level-1 headline whose raw value is exactly `References`. Parse `citation-reference` elements only inside that subtree and read their `:key` properties. Add/remove only standalone registry citation lines in that subtree. Do not scan the entire note for project membership.

For project selection, filter Org-roam nodes by the existing `p3/org-roam-filter-by-tag` helper or an equivalent `org-roam-node-tags` predicate for `project`; do not create a second project registry.

- [ ] **Step 7: Implement the classify/associate dispatcher and extend the central action menu**

`p3/reference-classify` should offer exactly these v1 operations:

```text
Add topic/status keyword
Remove topic/status keyword
Associate with project
Remove project association
```

The first two call Task 2 keyword helpers; the latter two mutate only project-note `* References` subtrees. Add `Open/create literature note` and `Classify / project association` to `p3/reference--action-alist` so global and project-scoped retrieval expose the same P3 actions.

- [ ] **Step 8: Run focused tests and verify Task 5 is green**

Expected: all Task 1–5 behavior tests PASS.

- [ ] **Step 9: Commit Task 5**

```bash
git add lisp/p3-reference.el test/p3-reference-test.el
git commit -m "Add reference notes and project associations"
```

---

### Task 6: Deterministic PDF attachments and lazy pdf-tools reading

**Files:**
- Modify: `lisp/p3-reference.el`
- Modify: `test/p3-reference-test.el`

**Interfaces:**
- Consumes: mature citekey contract; dynamically bound `p3/reference-pdf-directory`.
- Produces:
  - `p3/reference-pdf-path (citekey) -> absolute main.pdf path`
  - `p3/reference-open-pdf (&optional citekey) -> visits PDF, activates pdf-tools when usable, otherwise leaves normal Emacs fallback intact`
  - `p3/reference-attach-pdf (source-file &optional citekey) -> copies into <root>/<mature-key>/main.pdf`

- [ ] **Step 1: Write failing attachment-path and provisional-guard tests**

Assert:

```elisp
(let ((p3/reference-pdf-directory "/tmp/papers/"))
  (should (equal (p3/reference-pdf-path "smith2024")
                 "/tmp/papers/smith2024/main.pdf")))
```

Also assert:

- provisional keys are finalized before `p3/reference-attach-pdf` chooses a destination;
- merely asking for a path for a provisional key signals rather than returning a temporary-key directory;
- attaching creates the citekey directory lazily;
- repeated attachment requires explicit replacement confirmation and never silently overwrites `main.pdf`;
- supplemental files are not invented or auto-managed in v1.

- [ ] **Step 2: Run focused tests and verify they fail**

Expected: path/attachment tests fail.

- [ ] **Step 3: Implement deterministic attachment storage**

Keep the PDF root separate from the bibliography. Do not write absolute attachment paths into `references.bib`. `p3/reference-attach-pdf` copies a user-selected PDF into the deterministic mature-citekey directory only after finalization and overwrite confirmation.

- [ ] **Step 4: Add failing lazy-pdf-tools tests**

Stub `require`, `find-file`, and `pdf-view-mode` to prove:

- `p3-reference.el` can be loaded without pdf-tools;
- normal reference/citation functions do not call `require 'pdf-tools`;
- `p3/reference-open-pdf` opens the file first, then attempts `(require 'pdf-tools nil t)` only for that action;
- if pdf-tools is absent or `pdf-view-mode` errors because the native backend is unusable, the PDF remains open through Emacs's default viewer and a local message is emitted; the reference subsystem does not fail globally.

- [ ] **Step 5: Run focused tests and verify lazy-PDF cases fail**

Expected: attachment tests pass; lazy-reader tests fail.

- [ ] **Step 6: Implement the lazy reader and add PDF action to the central menu**

Use this failure shape:

```elisp
(find-file path)
(if (require 'pdf-tools nil t)
    (condition-case err
        (pdf-view-mode)
      (error
       (message "pdf-tools unavailable for this PDF: %s"
                (error-message-string err))))
  (message "pdf-tools is not installed; using Emacs's default PDF viewer"))
```

Add `Open PDF` to the Task 4 action menu. Do not invoke `pdf-tools-install` automatically and do not add platform-specific native-backend setup.

- [ ] **Step 7: Run focused tests and verify Task 6 is green**

Expected: all behavior tests PASS with no pdf-tools installation required by the test process.

- [ ] **Step 8: Commit Task 6**

```bash
git add lisp/p3-reference.el test/p3-reference-test.el
git commit -m "Add reference PDF attachment workflow"
```

---

### Task 7: Declarative reference owner, old citation cleanup, and discoverable bindings

**Files:**
- Create: `lisp/p3-config-reference.el`
- Create: `test/p3-config-reference-test.el`
- Modify: `config.org`
- Modify: `lisp/p3-config-org-roam.el`
- Modify: `test/p3-config-org-roam-test.el`
- Modify: `lisp/p3-config-base.el`
- Modify: `lisp/p3-commands.el`
- Modify: `test/p3-config-test.el`

**Interfaces:**
- Consumes: all behavior commands from Tasks 1–6.
- Produces:
  - `p3/reference-bibliography-file` default `~/org/references/references.bib`
  - `p3/reference-pdf-directory` default `~/papers/`
  - `p3/reference-command-map` with `a f i n p t r`
  - configuration feature `p3-config-reference`
  - one orchestration call `(p3/config-load-module 'p3-config-reference)` in `config.org`

- [ ] **Step 1: Write failing configuration-owner tests before creating the owner**

Model `test/p3-config-reference-test.el` after the existing focused config tests. Pin these contracts:

- configuration-owned path variables are defined before exact-source loading `p3-reference`;
- `p3-reference` exact-source load occurs before bindings/package integration that call its commands;
- Org-cite global bibliography and Citar bibliography both point to `(list p3/reference-bibliography-file)`;
- Org-cite insert/follow/activate processors are `citar`;
- Biblio is deferred and registers `("Save to P3 library" . p3/reference-biblio-save)` in `biblio-selection-mode-actions-alist`;
- pdf-tools is declared deferred/command-based and no `pdf-tools-install` call exists;
- `C-c b` is globally bound to `p3/reference-command-map`;
- command-map keys are exactly:

```text
a add reference
f find reference
i insert citation
n open/create literature note
p open PDF
t classify / project association
r current-project references
```

- no `citar-org-roam`, RefTeX citation configuration, or old direct `C-c b -> org-cite-insert` binding exists in the new owner.

- [ ] **Step 2: Run the focused config test and verify it fails**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-reference-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: FAIL because `p3-config-reference.el` does not exist.

- [ ] **Step 3: Create the declarative owner and reload-safe command map**

`p3-config-reference.el` should define the two `defcustom` paths first, then exact-source-load behavior:

```elisp
(defcustom p3/reference-bibliography-file
  (expand-file-name "~/org/references/references.bib")
  "Canonical personal BibLaTeX bibliography."
  :type 'file)

(defcustom p3/reference-pdf-directory
  (file-name-as-directory (expand-file-name "~/papers/"))
  "Root directory for citekey-organized reference PDFs."
  :type 'directory)

(p3/config-load-module 'p3-reference)
```

In `p3-reference.el`, define the map reload-safely rather than initializer-only:

```elisp
(defvar p3/reference-command-map nil)
(setq p3/reference-command-map
      (let ((map (make-sparse-keymap)))
        (define-key map (kbd "a") #'p3/reference-add)
        (define-key map (kbd "f") #'p3/reference-find)
        (define-key map (kbd "i") #'p3/reference-insert-citation)
        (define-key map (kbd "n") #'p3/reference-note)
        (define-key map (kbd "p") #'p3/reference-open-pdf)
        (define-key map (kbd "t") #'p3/reference-classify)
        (define-key map (kbd "r") #'p3/reference-project-references)
        map))
```

Use `use-package citar`, `use-package biblio`, and `use-package pdf-tools` declaratively; do not require their runtime features eagerly. The Biblio extended action is registered after Biblio loads.

- [ ] **Step 4: Run focused config + behavior tests and verify the owner is green before changing orchestration**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-reference-test.el \
  -l test/p3-config-reference-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS.

- [ ] **Step 5: Add failing architecture tests for orchestration cleanup and module count**

Update `test/p3-config-test.el` so it expects 14 `p3-config-*` owners including `p3-config-reference`. Pin that `config.org`:

- loads reference configuration at the former citation subsystem position, before completion;
- no longer contains `(use-package citar`, `(use-package citar-org-roam`, `reftex-default-bibliography`, `reftex-cite-format`, `bib-files-directory`, or `pdf-files-directory`;
- contains no inline reference workflow functions;
- retains the existing relative order of Completion and the later Org/Org-roam/Project/Python owners.

Expected ordering assertion:

```text
Editing < Reference < Completion < ESS < Org < Org-roam < Presentation < Project < Python < Terminal
```

Do not move unrelated subsystems merely to make this order easier to test.

- [ ] **Step 6: Add failing Org-roam regression for removal of the abandoned literature template**

Change `test/p3-config-org-roam-test.el` to expect only the durable default Org-roam capture template and the unchanged dailies template. Explicitly assert the config owner contains none of:

```text
citar-org-roam-subdir
citar-citekey
citar-date
note-title
```

This is an intentional behavior change: literature-note creation now belongs to `p3-reference.el`.

- [ ] **Step 7: Replace the old inline citation block and old Org-roam literature template**

In `config.org`, replace the entire `** Bibtex & citation-related` implementation with concise ownership prose plus:

```elisp
(p3/config-load-module 'p3-config-reference)
```

Remove the citar-org-roam-dependent `"n" "literature note"` capture template from `p3-config-org-roam.el`; preserve the normal capture template, dailies, bindings, display, and autosync behavior.

- [ ] **Step 8: Update Which-Key and the keybinding atlas, with tests**

In `p3-config-base.el`, add:

```text
C-c b   references
C-c b a add reference
C-c b f find reference
C-c b i insert citation
C-c b n literature note
C-c b p open reference PDF
C-c b t classify / associate
C-c b r project references
```

In `p3-commands.el`, remove `("C-c b" . "insert citation")` from the Org section and add a References section with the same seven workflow bindings. Extend existing config/commands tests to pin that atlas transition.

- [ ] **Step 9: Run all focused architecture tests**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-reference-test.el \
  -l test/p3-config-reference-test.el \
  -l test/p3-config-org-roam-test.el \
  -l test/p3-config-test.el \
  -l test/p3-commands-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS with 14 config owners and no old citation/RefTeX/citar-org-roam configuration left inline.

- [ ] **Step 10: Commit Task 7**

```bash
git add config.org \
  lisp/p3-reference.el \
  lisp/p3-config-reference.el \
  lisp/p3-config-org-roam.el \
  lisp/p3-config-base.el \
  lisp/p3-commands.el \
  test/p3-config-reference-test.el \
  test/p3-config-org-roam-test.el \
  test/p3-config-test.el \
  test/p3-commands-test.el
git commit -m "Integrate portable reference workflow"
```

---

### Task 8: Durable reconstruction regression and bounded CI integration

**Files:**
- Modify: `test/p3-reference-test.el`
- Modify: `.github/workflows/emacs-tests.yml`
- Modify: `.github/workflows/windows-platform-tests.yml`

**Interfaces:**
- Consumes: complete v1 behavior/config boundary.
- Produces: regression evidence that durable relationships can be reconstructed from plain BibLaTeX/Org plus one coherent Ubuntu/Windows CI gate.

- [ ] **Step 1: Write the architecture-level reconstruction test**

Create temporary plain files only:

```text
references.bib
roam/project.org
roam/literature.org
```

Populate them with:

```bibtex
@article{alpha2020,
  title = {Alpha Study},
  author = {Alpha, Ada},
  year = {2020}
}
```

```org
#+title: Project
#+filetags: :project:

* References
[cite:@alpha2020]
```

```org
:PROPERTIES:
:ID: literature-alpha
:ROAM_REFS: @alpha2020
:END:
#+title: Alpha Study
#+filetags: :literature:
```

The test must not load or consult Citar, Biblio, pdf-tools, or any private P3 cache. Using only BibTeX/Org parsing, assert that `alpha2020` is recoverable as:

- one bibliography identity;
- one project association;
- one literature-note reference.

This test proves the architecture, not merely the implementation helpers.

- [ ] **Step 2: Run the complete local ERT suite before editing CI**

Run the same full test command used by `.github/workflows/emacs-tests.yml`, adding the two new test files:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-loader-test.el \
  -l test/p3-config-test.el \
  -l test/p3-config-ess-test.el \
  -l test/p3-project-test.el \
  -l test/p3-config-project-test.el \
  -l test/p3-core-test.el \
  -l test/p3-platform-test.el \
  -l test/p3-config-python-test.el \
  -l test/p3-python-test.el \
  -l test/p3-terminal-test.el \
  -l test/p3-config-terminal-test.el \
  -l test/p3-ess-test.el \
  -l test/p3-gptel-test.el \
  -l test/p3-config-gptel-test.el \
  -l test/p3-r-tools-test.el \
  -l test/p3-org-test.el \
  -l test/p3-config-org-test.el \
  -l test/p3-org-roam-test.el \
  -l test/p3-config-org-roam-test.el \
  -l test/p3-org-present-test.el \
  -l test/p3-config-org-present-test.el \
  -l test/p3-org-export-test.el \
  -l test/p3-reference-test.el \
  -l test/p3-config-reference-test.el \
  -l test/p3-commands-test.el \
  -l test/p3-git-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS with zero unexpected failures. If the execution environment lacks Emacs, record that as an environment limitation and do not substitute repeated CI runs for local diagnosis.

- [ ] **Step 3: Add Ubuntu compile/smoke/test coverage**

In `.github/workflows/emacs-tests.yml`:

- add `lisp/p3-reference.el` and `lisp/p3-config-reference.el` to byte compilation;
- add a focused `Smoke-load Reference configuration boundary` step that stubs external package features sufficiently to verify the owner loads, the behavior feature is present, the two default paths are configured, and `C-c b` resolves to `p3/reference-command-map` without touching any real bibliography or PDF directory;
- add `test/p3-reference-test.el` and `test/p3-config-reference-test.el` to the full ERT command.

The smoke must not contact Crossref/DOI services and must not initialize pdf-tools native support.

- [ ] **Step 4: Add Windows architecture coverage without adding a native-PDF job**

In `.github/workflows/windows-platform-tests.yml`:

- add `lisp/p3-reference.el`, `lisp/p3-config-reference.el`, `test/p3-reference-test.el`, and `test/p3-config-reference-test.el` to `pull_request.paths`;
- byte-compile `lisp/p3-reference.el` because its core must remain platform-neutral;
- include `test/p3-config-reference-test.el` and the platform-neutral subset of `test/p3-reference-test.el` in the Windows architecture test command;
- do not install or invoke pdf-tools native support on Windows in this PR.

If a behavior test is inherently Unix-path-specific, fix the test to use `make-temp-file`/`expand-file-name` rather than excluding it from Windows.

- [ ] **Step 5: Run static plan/spec acceptance checks before pushing**

Inspect the branch and verify all of these directly:

```text
no use-package citar-org-roam
no reftex-default-bibliography/reftex-cite-format
no mature-key rename command
no generic webpage scraper
no pdf-tools-install call
exactly one p3-config-reference orchestration call
14 p3-config-* owners
C-c b prefix plus a/f/i/n/p/t/r only
```

Also inspect the diff to confirm bibliography workflow code lives in the two new reference modules rather than leaking back into `config.org` or `p3-org-roam.el`.

- [ ] **Step 6: Commit the CI/reconstruction gate**

```bash
git add test/p3-reference-test.el \
  .github/workflows/emacs-tests.yml \
  .github/workflows/windows-platform-tests.yml
git commit -m "Verify portable reference workflow"
```

- [ ] **Step 7: Push once and run the coherent CI gate**

Push the implementation branch and open/update the PR. Use the normal pull-request-triggered Ubuntu and Windows workflows once. Treat these as authoritative only for boundaries unavailable locally.

Expected final evidence:

```text
Ubuntu: byte compilation PASS
Ubuntu: Reference config smoke PASS
Ubuntu: full ERT PASS, 0 unexpected
Windows: platform/project tests PASS
Windows: config/reference architecture tests PASS
```

If one workflow fails, inspect the exact failing step/log first. Do not add diagnostic workflows or repeatedly rerun full CI without a root-cause hypothesis.

- [ ] **Step 8: Adversarially review the finished PR before requesting merge approval**

Review against the approved spec, especially:

- data-loss risk in bibliography mutation;
- accidental mature citekey changes;
- hidden package/cache state;
- narrative-citation/project-registry confusion;
- startup coupling to missing knowledge files or pdf-tools;
- unexpected changes to Org-roam capture behavior beyond removal of the abandoned Citar template;
- platform-specific path assumptions;
- any feature or package added outside v1 scope.

Fix blockers/high findings test-first, rerun focused tests, and use another full CI gate only if the reviewed head changes in runtime-relevant ways. Do not merge without explicit user approval.
