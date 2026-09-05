# Emacs Reference Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an Emacs-owned, plain-file reference workflow that safely captures, retrieves, cites, classifies, project-associates, notes, and opens publications without making any package-specific database authoritative.

**Architecture:** `references.bib` is the canonical BibLaTeX database; Org files are the canonical literature-note and project-association graph; PDFs are optional files under a configurable citekey-based root. `p3-reference.el` owns the stable workflow and data-safety rules, while `p3-config-reference.el` owns Citar, Biblio, Org-cite, pdf-tools, paths, and the `C-c b` prefix. Citar supplies bibliography selection, Biblio supplies DOI/Crossref acquisition, Org-roam supplies note/project nodes, and pdf-tools is a lazy reader. All durable identity and relationships remain reconstructable from BibLaTeX and Org alone.

**Tech Stack:** Emacs 29+ Lisp, built-in `bibtex`, Org/Org-cite, Org-roam, Citar, Biblio.el, optional/lazy pdf-tools, ERT, the existing exact-source config loader, GitHub Actions on Ubuntu and Windows.

**Spec:** `docs/superpowers/specs/2026-09-05-reference-management-design.md`

## Global Constraints

- `references.bib` and Org files are authoritative; no private package cache or database may become required state.
- A citekey beginning with `p3-inbox-` is provisional; no keyword or other field may substitute for this test.
- Provisional records cannot be cited, linked to a literature note, associated with a project, or assigned a citekey-based attachment path until finalized.
- Mature citekeys are unique and immutable in v1; do not add mature-key migration/rename machinery.
- Bibliography mutations preserve unrelated text where practical, validate a same-filesystem temporary candidate, verify unique citekeys, and atomically replace the original only after validation succeeds.
- Enrichment fills blank fields automatically but never silently overwrites populated conflicting fields.
- DOI and normalized-URL equality are strong duplicate signals; normalized-title equality is only a possible-duplicate warning and never an automatic merge.
- URL capture may recognize a DOI but must not grow into generic webpage scraping or site-specific metadata extraction.
- Project associations live only as unique native Org citations under one top-level `* References` subtree in a `:project:` Org-roam note; narrative citations elsewhere do not become associations.
- Citation indexing/backlinks caused by project-registry citations are intentional.
- The reference subsystem must load without the user's bibliography, PDFs, Org-roam availability, or a working pdf-tools native backend.
- pdf-tools is lazy/non-fatal; do not make its native backend a startup prerequisite and do not add Windows-specific PDF setup to this PR.
- The current Org-local `C-c b -> org-cite-insert` binding is intentionally replaced by the reference prefix; citation insertion moves to `C-c b i`.
- Preserve the existing user-data roots by default: bibliography `~/org/bib/main.bib`, PDF root `~/org/lib/`. Relocating user data is not part of this PR; both remain customizable.
- Do not preserve the abandoned RefTeX/citar-org-roam experiment merely for compatibility.
- Do not add Zotero, Better BibTeX, org-ref, org-roam-bibtex, citar-org-roam, Ebib, helm-bibtex/ivy-bibtex, browser scraping, PDF synchronization, org-noter, or org-pdftools in v1.
- Keep GitHub Actions bounded: run focused batch tests while implementing, then one coherent PR CI gate; use another full CI run only when a runtime-relevant fix changes the reviewed head.
- Do not merge without explicit user approval.

---

## File Map

**Create**

- `lisp/p3-reference.el` — safe BibLaTeX mutation, capture/finalization/enrichment, Citar-facing retrieval actions, Org-roam/project integration, and attachment resolution.
- `lisp/p3-config-reference.el` — path variables, Citar/Biblio/Org-cite/pdf-tools declarations, and global `C-c b` binding.
- `test/p3-reference-test.el` — behavior/data-integrity tests using temporary bibliographies, temporary Org files, and package API stubs.
- `test/p3-config-reference-test.el` — declarative ownership, command-map, dependency-laziness, and old-config-removal tests.

**Modify**

- `config.org` — replace the abandoned inline BibTeX/RefTeX/Citar block with one `p3-config-reference` owner call.
- `lisp/p3-config-org-roam.el` — remove the old citar-org-roam-dependent literature capture template; preserve ordinary Org-roam behavior.
- `test/p3-config-org-roam-test.el` — pin that capture-template change.
- `lisp/p3-config-base.el` — add Which-Key labels for `C-c b` and its seven v1 actions.
- `lisp/p3-commands.el` — replace the old Org citation atlas entry with a References section.
- `test/p3-config-test.el` — raise owner count to 14, pin reference-owner placement, and forbid old inline citation machinery.
- `test/p3-commands-test.el` — pin the keybinding-atlas transition.
- `.github/workflows/emacs-tests.yml` — compile/smoke/test the new boundary on Ubuntu.
- `.github/workflows/windows-platform-tests.yml` — cover platform-neutral reference code/config without invoking pdf-tools native support.

---

### Task 1: Safe bibliography storage and provisional-state core

**Files:**
- Create: `lisp/p3-reference.el`
- Create: `test/p3-reference-test.el`

**Interfaces:**
- Consumes: built-in `bibtex`; dynamically bound `p3/reference-bibliography-file`.
- Produces:
  - `p3/reference-provisional-key-p (citekey) -> boolean`
  - `p3/reference--new-provisional-key () -> string`
  - `p3/reference--bibliography-path () -> absolute path or user-error`
  - `p3/reference--goto-entry (citekey) -> boolean`
  - `p3/reference--entry-alist (citekey) -> alist or nil`
  - `p3/reference--entry-keys-from-content (content) -> list[string]`
  - `p3/reference--validate-content (content) -> t or signal`
  - `p3/reference--transaction (edit-fn) -> edit-fn result`

- [ ] **Step 1: Add a reusable temporary-library test harness and the first failing tests**

Create `test/p3-reference-test.el` with:

```elisp
;;; p3-reference-test.el --- Reference workflow tests -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)

(defconst p3-reference-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))
(add-to-list 'load-path (expand-file-name "lisp" p3-reference-test--root))
(require 'p3-reference)

(defmacro p3-reference-test--with-library (content &rest body)
  (declare (indent 1))
  `(let* ((directory (make-temp-file "p3-reference-" t))
          (p3/reference-bibliography-file
           (expand-file-name "references.bib" directory))
          (p3/reference-pdf-directory
           (expand-file-name "papers/" directory)))
     (unwind-protect
         (progn
           (when ,content
             (with-temp-file p3/reference-bibliography-file
               (insert ,content)))
           ,@body)
       (delete-directory directory t))))

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

(ert-deftest p3-reference-load-does-not-create-bibliography ()
  (p3-reference-test--with-library nil
    (should-not (file-exists-p p3/reference-bibliography-file))
    (should (featurep 'p3-reference))
    (should-not (file-exists-p p3/reference-bibliography-file))))
```

- [ ] **Step 2: Run the focused tests and verify red**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-reference-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: FAIL because `p3-reference.el` does not exist.

- [ ] **Step 3: Add the load-safe behavior skeleton**

Create `lisp/p3-reference.el` using only built-ins at load time:

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

(provide 'p3-reference)
```

Do not require Citar, Biblio, Org-roam, or pdf-tools here.

- [ ] **Step 4: Add complete failing integrity tests**

Add:

```elisp
(defconst p3-reference-test--two-entries
  "@article{alpha2020,\n  title = {Alpha},\n  doi = {10.1000/alpha}\n}\n\n% keep this comment exactly\n@article{beta2021,\n  title = {Beta}\n}\n")

(ert-deftest p3-reference-validation-rejects-duplicate-keys ()
  (should-error
   (p3/reference--validate-content
    "@article{x, title={A}}\n@book{x, title={B}}\n")))

(ert-deftest p3-reference-validation-rejects-malformed-bibtex ()
  (should-error
   (p3/reference--validate-content
    "@article{x, title={Unclosed}\n")))

(ert-deftest p3-reference-transaction-leaves-original-on-validation-failure ()
  (p3-reference-test--with-library p3-reference-test--two-entries
    (let ((before (with-temp-buffer
                    (insert-file-contents p3/reference-bibliography-file)
                    (buffer-string))))
      (should-error
       (p3/reference--transaction
        (lambda ()
          (goto-char (point-max))
          (insert "\n@article{alpha2020, title={Duplicate}}\n"))))
      (should (equal before
                     (with-temp-buffer
                       (insert-file-contents p3/reference-bibliography-file)
                       (buffer-string)))))))

(ert-deftest p3-reference-targeted-edit-preserves-unrelated-tail ()
  (p3-reference-test--with-library p3-reference-test--two-entries
    (let ((tail "% keep this comment exactly\n@article{beta2021,\n  title = {Beta}\n}\n"))
      (p3/reference--transaction
       (lambda ()
         (should (p3/reference--goto-entry "alpha2020"))
         (bibtex-set-field "title" "Alpha revised")))
      (with-temp-buffer
        (insert-file-contents p3/reference-bibliography-file)
        (should (string-suffix-p tail (buffer-string)))))))
```

- [ ] **Step 5: Run focused tests and verify the new cases fail**

Expected: provisional tests PASS; integrity tests FAIL because transaction/validation helpers are absent.

- [ ] **Step 6: Implement targeted validated atomic transactions**

Implement `p3/reference--bibliography-path`, `p3/reference--goto-entry`, and parsing helpers over a `bibtex-mode` buffer. `p3/reference--validate-content` must use built-in BibTeX parsing to reject malformed ordinary entries, collect ordinary citekeys while excluding `@string`, `@preamble`, and `@comment`, and reject duplicate keys.

Implement the transaction with a same-directory temporary file:

```elisp
(defun p3/reference--transaction (edit-fn)
  (let* ((target (p3/reference--bibliography-path))
         (directory (file-name-directory target))
         (original (if (file-exists-p target)
                       (with-temp-buffer
                         (insert-file-contents target)
                         (buffer-string))
                     ""))
         result candidate temp)
    (make-directory directory t)
    (with-temp-buffer
      (insert original)
      (bibtex-mode)
      (bibtex-set-dialect 'biblatex t)
      (setq result (funcall edit-fn)
            candidate (buffer-string)))
    (p3/reference--validate-content candidate)
    (setq temp
          (make-temp-file
           (expand-file-name ".p3-references-" directory)
           nil ".bib" candidate))
    (unwind-protect
        (progn
          (when (file-exists-p target)
            (set-file-modes temp (file-modes target)))
          (rename-file temp target t)
          (setq temp nil))
      (when (and temp (file-exists-p temp))
        (delete-file temp)))
    result))
```

The edit callback works on the full text buffer but must mutate only its target entry/append location. Do not parse and reserialize the whole library.

- [ ] **Step 7: Run focused tests and verify Task 1 green**

Expected: all Task 1 tests PASS without any external package.

- [ ] **Step 8: Commit Task 1**

```bash
git add lisp/p3-reference.el test/p3-reference-test.el
git commit -m "Add safe reference bibliography core"
```

---

### Task 2: Import, duplicates, classification, and citekey finalization

**Files:**
- Modify: `lisp/p3-reference.el`
- Modify: `test/p3-reference-test.el`

**Interfaces:**
- Consumes: Task 1 transaction/entry helpers.
- Produces:
  - `p3/reference-normalize-doi (doi) -> string or nil`
  - `p3/reference-normalize-url (url) -> string or nil`
  - `p3/reference-import-bibtex (bibtex) -> canonical citekey`
  - `p3/reference-add-keyword (citekey keyword) -> t`
  - `p3/reference-remove-keyword (citekey keyword) -> t`
  - `p3/reference--propose-citekey (citekey) -> generated key or nil`
  - `p3/reference-finalize (citekey) -> mature citekey`

- [ ] **Step 1: Add complete normalization/duplicate tests**

```elisp
(ert-deftest p3-reference-normalizes-doi-and-url ()
  (should (equal (p3/reference-normalize-doi
                  " https://doi.org/10.1000/ABC ")
                 "10.1000/abc"))
  (should (equal (p3/reference-normalize-url
                  "HTTPS://Example.COM/paper/#section")
                 "https://example.com/paper")))

(ert-deftest p3-reference-import-doi-duplicate-does-not-append ()
  (p3-reference-test--with-library
      "@article{alpha2020, title={Alpha}, doi={10.1000/alpha}}\n"
    (should
     (equal "alpha2020"
            (p3/reference-import-bibtex
             "@article{other, title={Other}, doi={https://doi.org/10.1000/ALPHA}}")))
    (with-temp-buffer
      (insert-file-contents p3/reference-bibliography-file)
      (should (= 1 (how-many "^@" (point-min) (point-max)))))))

(ert-deftest p3-reference-import-url-duplicate-does-not-append ()
  (p3-reference-test--with-library
      "@online{alpha2020, title={Alpha}, url={https://example.com/paper/}}\n"
    (should
     (equal "alpha2020"
            (p3/reference-import-bibtex
             "@online{other, title={Other}, url={HTTPS://EXAMPLE.COM/paper#top}}")))))

(ert-deftest p3-reference-title-match-never-auto-merges ()
  (p3-reference-test--with-library
      "@article{alpha2020, title={A Useful Study}}\n"
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) nil)))
      (should-error
       (p3/reference-import-bibtex
        "@article{beta2021, title={A useful study!}}")))
    (with-temp-buffer
      (insert-file-contents p3/reference-bibliography-file)
      (should-not (search-forward "beta2021" nil t)))))
```

- [ ] **Step 2: Run focused tests and verify red**

Expected: normalization/import tests FAIL; Task 1 remains green.

- [ ] **Step 3: Implement canonical duplicate checks and one-entry import**

`p3/reference-import-bibtex` must require exactly one ordinary entry, parse its key/DOI/URL/title, reject an incoming `p3-inbox-*` key as a structured mature import, and check the canonical file directly. Strong DOI/URL matches return the existing citekey without adding a record. A normalized-title match prompts with `y-or-n-p`; declining signals/cancels without mutation, accepting adds a distinct record. The append occurs through `p3/reference--transaction` and retains the supplied entry text rather than rewriting existing entries.

- [ ] **Step 4: Add complete keyword/finalization tests**

```elisp
(ert-deftest p3-reference-status-inbox-is-not-technical-provisional-state ()
  (p3-reference-test--with-library
      "@article{alpha2020, title={Alpha}, keywords={status/inbox}}\n"
    (should-not (p3/reference-provisional-key-p "alpha2020"))))

(ert-deftest p3-reference-keywords-are-entry-local-and-idempotent ()
  (p3-reference-test--with-library p3-reference-test--two-entries
    (p3/reference-add-keyword "alpha2020" "quantitative-methods")
    (p3/reference-add-keyword "alpha2020" "quantitative-methods")
    (let ((entry (p3/reference--entry-alist "alpha2020")))
      (should (equal "quantitative-methods" (cdr (assoc "keywords" entry)))))
    (should (equal "Beta" (cdr (assoc "title" (p3/reference--entry-alist "beta2021")))))))

(ert-deftest p3-reference-finalize-leaves-mature-key-unchanged ()
  (p3-reference-test--with-library "@article{alpha2020, title={Alpha}}\n"
    (should (equal "alpha2020" (p3/reference-finalize "alpha2020")))))

(ert-deftest p3-reference-finalize-needs-a-usable-generated-key ()
  (p3-reference-test--with-library
      "@online{p3-inbox-1, url={https://example.com}}\n"
    (cl-letf (((symbol-function 'p3/reference--propose-citekey)
               (lambda (_key) nil)))
      (should-error (p3/reference-finalize "p3-inbox-1")))))

(ert-deftest p3-reference-finalize-renames-only-provisional-head ()
  (p3-reference-test--with-library
      "@article{p3-inbox-1, title={Alpha}, author={Ada Alpha}, year={2020}}\n@article{beta2021, title={Beta}}\n"
    (cl-letf (((symbol-function 'p3/reference--propose-citekey)
               (lambda (_key) "alpha2020"))
              ((symbol-function 'read-string)
               (lambda (&rest _) "alpha2020")))
      (should (equal "alpha2020" (p3/reference-finalize "p3-inbox-1"))))
    (should (p3/reference--entry-alist "alpha2020"))
    (should (p3/reference--entry-alist "beta2021"))
    (should-not (p3/reference--entry-alist "p3-inbox-1"))))

(ert-deftest p3-reference-finalize-rejects-colliding-mature-key ()
  (p3-reference-test--with-library
      "@article{p3-inbox-1, title={Alpha}}\n@article{alpha2020, title={Existing}}\n"
    (cl-letf (((symbol-function 'p3/reference--propose-citekey)
               (lambda (_key) "alpha2020"))
              ((symbol-function 'read-string)
               (lambda (&rest _) "alpha2020")))
      (should-error (p3/reference-finalize "p3-inbox-1")))))
```

- [ ] **Step 5: Run focused tests and verify the new cases red**

Expected: import tests PASS; keyword/finalization tests FAIL.

- [ ] **Step 6: Implement entry-local keywords and finalization**

Use `bibtex-set-field` only after locating the target entry. Split `keywords` on commas, trim/de-duplicate, and write the resulting single field.

`p3/reference--propose-citekey` must isolate the provisional entry in a temporary BibTeX buffer and call built-in `bibtex-generate-autokey`. If generation errors or returns empty, finalization reports that the record needs enrichment/manual metadata before it can become durable. `p3/reference-finalize` shows the proposal through `read-string`, rejects empty/reserved/colliding keys, then replaces only the entry-head key inside a validated transaction. It returns mature keys unchanged and exposes no mature-key rename operation.

- [ ] **Step 7: Run focused tests and verify Task 2 green**

- [ ] **Step 8: Commit Task 2**

```bash
git add lisp/p3-reference.el test/p3-reference-test.el
git commit -m "Add reference import and finalization"
```

---

### Task 3: Capture and enrichment through Biblio without hidden state

**Files:**
- Modify: `lisp/p3-reference.el`
- Modify: `test/p3-reference-test.el`

**Interfaces:**
- Consumes: Task 2 import/finalization; Biblio APIs only when acquisition is invoked.
- Produces:
  - `p3/reference-add (&optional input)`
  - `p3/reference--input-kind (input) -> 'bibtex | 'doi | 'url | 'search`
  - `p3/reference--doi-in-string (string) -> DOI or nil`
  - `p3/reference--capture-url (url) -> provisional citekey`
  - `p3/reference-merge-bibtex (target-key bibtex) -> target-key`
  - buffer-local `p3/reference--biblio-target-key`
  - `p3/reference-biblio-save (metadata)`
  - `p3/reference-enrich (citekey)`

- [ ] **Step 1: Add complete routing/offline-capture tests**

```elisp
(ert-deftest p3-reference-routes-capture-inputs ()
  (should (eq 'bibtex (p3/reference--input-kind "@article{x, title={X}}")))
  (should (eq 'doi (p3/reference--input-kind "10.1000/xyz")))
  (should (eq 'doi (p3/reference--input-kind "https://doi.org/10.1000/xyz")))
  (should (eq 'url (p3/reference--input-kind "https://example.org/article")))
  (should (eq 'search (p3/reference--input-kind "Smith 2024 measurement error")))
  (should (eq 'search (p3/reference--input-kind
                      "Smith, A. (2024). Measurement Error. Journal 2(1)."))))

(ert-deftest p3-reference-url-only-capture-is-offline-and-provisional ()
  (p3-reference-test--with-library nil
    (cl-letf (((symbol-function 'url-retrieve)
               (lambda (&rest _) (ert-fail "URL retrieval is forbidden"))))
      (let ((key (p3/reference--capture-url "https://example.org/article")))
        (should (p3/reference-provisional-key-p key))
        (let ((entry (p3/reference--entry-alist key)))
          (should (equal "https://example.org/article"
                         (cdr (assoc "url" entry))))
          (should (string-match-p "status/inbox"
                                  (cdr (assoc "keywords" entry)))))))))
```

- [ ] **Step 2: Run focused tests and verify red**

- [ ] **Step 3: Implement one-prompt capture routing and provisional URL save**

`p3/reference-add` prompts once when INPUT is nil. Dispatch exactly:

```elisp
(pcase (p3/reference--input-kind input)
  ('bibtex (p3/reference-import-bibtex input))
  ('doi    (p3/reference--lookup-doi input))
  ('url    (p3/reference--capture-url input))
  ('search (p3/reference--lookup-title input)))
```

A URL without a directly recognizable DOI is appended immediately as one `@online{p3-inbox-..., ...}` record with `url`, current `urldate`, and `keywords={status/inbox}`. It never fetches the webpage.

- [ ] **Step 4: Add complete Biblio acquisition/enrichment tests with stubs**

```elisp
(ert-deftest p3-reference-doi-result-enters-safe-import-path ()
  (p3-reference-test--with-library nil
    (let (imported)
      (cl-letf (((symbol-function 'require) (lambda (&rest _) t))
                ((symbol-function 'biblio-cleanup-doi) #'identity)
                ((symbol-function 'biblio-format-bibtex) (lambda (text _autokey) text))
                ((symbol-function 'biblio-doi-forward-bibtex)
                 (lambda (_doi callback)
                   (funcall callback "@article{alpha2020, title={Alpha}, doi={10.1000/alpha}}")))
                ((symbol-function 'p3/reference-import-bibtex)
                 (lambda (text) (setq imported text) "alpha2020")))
        (p3/reference--lookup-doi "10.1000/alpha")
        (should (string-match-p "alpha2020" imported))))))

(ert-deftest p3-reference-enrichment-fills-blank-field-without-changing-key ()
  (p3-reference-test--with-library
      "@article{p3-inbox-1, title={Alpha}, year={}}\n"
    (p3/reference-merge-bibtex
     "p3-inbox-1"
     "@article{remote, title={Alpha}, year={2024}, doi={10.1000/alpha}}")
    (let ((entry (p3/reference--entry-alist "p3-inbox-1")))
      (should (equal "2024" (cdr (assoc "year" entry))))
      (should (equal "10.1000/alpha" (cdr (assoc "doi" entry)))))))

(ert-deftest p3-reference-enrichment-does-not-silently-overwrite-conflict ()
  (p3-reference-test--with-library
      "@article{p3-inbox-1, title={My corrected title}, year={2024}}\n"
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) nil)))
      (p3/reference-merge-bibtex
       "p3-inbox-1"
       "@article{remote, title={Remote title}, year={2024}}"))
    (should (equal "My corrected title"
                   (cdr (assoc "title"
                               (p3/reference--entry-alist "p3-inbox-1")))))))

(ert-deftest p3-reference-biblio-action-enriches-target-instead-of-duplicating ()
  (p3-reference-test--with-library
      "@article{p3-inbox-1, title={Alpha}}\n"
    (let ((p3/reference--biblio-target-key "p3-inbox-1"))
      (cl-letf (((symbol-function 'biblio-format-bibtex) (lambda (text _autokey) text)))
        (p3/reference-biblio-save
         `((backend . ,(lambda (command metadata callback)
                         (ignore metadata)
                         (when (eq command 'forward-bibtex)
                           (funcall callback
                                    "@article{remote, title={Alpha}, year={2024}}"))))))))
    (should (p3/reference--entry-alist "p3-inbox-1"))
    (should-not (p3/reference--entry-alist "remote"))))
```

- [ ] **Step 5: Run focused tests and verify the acquisition/enrichment cases red**

- [ ] **Step 6: Implement Biblio integration using its public backend protocol**

DOI lookup lazily requires `biblio-doi` and calls `biblio-doi-forward-bibtex`; title/formatted-citation lookup lazily requires `biblio-crossref` and calls `biblio-crossref-lookup` with the original text. Format returned BibTeX with `biblio-format-bibtex` before safe import/merge.

Define:

```elisp
(defvar-local p3/reference--biblio-target-key nil)
```

`p3/reference-biblio-save` reads the current result metadata's `backend` and invokes its documented `'forward-bibtex` command. If `p3/reference--biblio-target-key` is nil, import a new mature record. If non-nil, call `p3/reference-merge-bibtex` on that existing provisional record so enrichment cannot create a second identity.

`p3/reference-merge-bibtex` parses incoming fields but ignores the remote `=key=`/`=type=` identity. For each incoming field: fill a missing/empty target field automatically; leave equal values alone; for a populated conflicting target field, ask `y-or-n-p` before replacing it. All changes occur entry-locally through Task 1's validated transaction.

`p3/reference-enrich` uses DOI directly when present. Otherwise it launches `biblio-crossref-lookup` with the best available title (falling back to URL text only when title is absent), captures the returned result buffer, and sets `p3/reference--biblio-target-key` buffer-locally there. Keep enrichment callable via `M-x`; the approved v1 prefix does not add an `e` binding.

- [ ] **Step 7: Run focused tests and verify Task 3 green**

- [ ] **Step 8: Commit Task 3**

```bash
git add lisp/p3-reference.el test/p3-reference-test.el
git commit -m "Add reference capture and enrichment"
```

---

### Task 4: Citar-backed retrieval and native Org citation insertion

**Files:**
- Modify: `lisp/p3-reference.el`
- Modify: `test/p3-reference-test.el`

**Interfaces:**
- Consumes: Task 2 finalization; Citar only when retrieval/citation commands run.
- Produces:
  - `p3/reference--select-key (&optional allowed-keys) -> citekey or nil`
  - `p3/reference-find (&optional allowed-keys)`
  - `p3/reference-insert-citation (&optional citekey)`
  - `p3/reference-open-url (&optional citekey)`
  - `p3/reference-edit-entry (&optional citekey)`
  - `p3/reference--action-alist ()`

- [ ] **Step 1: Add complete Citar-wrapper tests**

```elisp
(ert-deftest p3-reference-project-filter-is-passed-to-citar-selection ()
  (let (filter)
    (cl-letf (((symbol-function 'require) (lambda (&rest _) t))
              ((symbol-function 'citar-select-ref)
               (lambda (&rest args)
                 (setq filter (plist-get args :filter))
                 "beta2021")))
      (should (equal "beta2021"
                     (p3/reference--select-key '("alpha2020" "beta2021"))))
      (should (funcall filter "alpha2020"))
      (should-not (funcall filter "gamma2022")))))

(ert-deftest p3-reference-empty-project-set-never-falls-back-to-global-search ()
  (cl-letf (((symbol-function 'citar-select-ref)
             (lambda (&rest _) (ert-fail "Citar must not be called"))))
    (should-error (p3/reference--select-key '()))))

(ert-deftest p3-reference-url-action-falls-back-to-doi ()
  (let (opened)
    (cl-letf (((symbol-function 'citar-get-value)
               (lambda (field _key)
                 (pcase field
                   ("url" nil)
                   ("doi" "10.1000/alpha"))))
              ((symbol-function 'browse-url)
               (lambda (url &rest _) (setq opened url))))
      (p3/reference-open-url "alpha2020")
      (should (equal "https://doi.org/10.1000/alpha" opened)))))
```

- [ ] **Step 2: Run focused tests and verify red**

- [ ] **Step 3: Implement one selection model and one P3 action dispatcher**

`p3/reference--select-key` calls `citar-select-ref`; when `allowed-keys` is non-nil it passes a predicate matching only those keys. An explicitly empty list is a no-results condition, not global search.

`p3/reference-find` selects one key and then uses one standard `completing-read` action menu. Start the v1 menu with `Insert citation`, `Open URL`, and `Edit bibliography entry`; Tasks 5–6 extend the same alist with note/project/PDF actions. Do not add citar-embark solely to compose this menu.

- [ ] **Step 4: Add complete provisional-citation tests**

```elisp
(ert-deftest p3-reference-insert-citation-finalizes-provisional-first ()
  (let (inserted)
    (cl-letf (((symbol-function 'require) (lambda (&rest _) t))
              ((symbol-function 'p3/reference-finalize)
               (lambda (_key) "alpha2020"))
              ((symbol-function 'citar-insert-citation)
               (lambda (keys &optional _arg) (setq inserted keys))))
      (p3/reference-insert-citation "p3-inbox-1")
      (should (equal '("alpha2020") inserted)))))

(ert-deftest p3-reference-insert-citation-does-not-finalize-mature-status-inbox ()
  (let (finalized inserted)
    (cl-letf (((symbol-function 'require) (lambda (&rest _) t))
              ((symbol-function 'p3/reference-finalize)
               (lambda (key) (setq finalized key) key))
              ((symbol-function 'citar-insert-citation)
               (lambda (keys &optional _arg) (setq inserted keys))))
      (p3/reference-insert-citation "alpha2020")
      (should-not finalized)
      (should (equal '("alpha2020") inserted)))))
```

- [ ] **Step 5: Run focused tests and verify citation cases red**

- [ ] **Step 6: Implement citation insertion through Citar/Org-cite**

For a provisional key, call `p3/reference-finalize` first; for a mature key, do not invoke finalization. Then call `citar-insert-citation` with the final key list. Do not hand-build `[cite:@...]` text inside P3; native Org/Citar processors remain responsible for document citation syntax.

- [ ] **Step 7: Run focused tests and verify Task 4 green**

- [ ] **Step 8: Commit Task 4**

```bash
git add lisp/p3-reference.el test/p3-reference-test.el
git commit -m "Add reference retrieval and citation actions"
```

---

### Task 5: Org-roam literature notes and project-reference registries

**Files:**
- Modify: `lisp/p3-reference.el`
- Modify: `test/p3-reference-test.el`

**Interfaces:**
- Consumes: mature citekeys and Task 4 action selector; Org-roam only when note/project commands run.
- Produces:
  - `p3/reference-note (&optional citekey)`
  - `p3/reference--project-node-p (node) -> boolean`
  - `p3/reference--current-project-node () -> node or nil`
  - `p3/reference--select-project-node () -> project node`
  - `p3/reference-project-citekeys (&optional node) -> list[string]`
  - `p3/reference-associate-project (citekey &optional node)`
  - `p3/reference-remove-project-association (citekey &optional node)`
  - `p3/reference-project-references (&optional node)`
  - `p3/reference-classify (&optional citekey)`

- [ ] **Step 1: Add complete literature-note tests**

```elisp
(ert-deftest p3-reference-note-opens-existing-ref-node ()
  (let (visited)
    (cl-letf (((symbol-function 'require) (lambda (&rest _) t))
              ((symbol-function 'org-roam-node-from-ref)
               (lambda (ref) (and (equal ref "@alpha2020") 'existing-node)))
              ((symbol-function 'org-roam-node-visit)
               (lambda (node &rest _) (setq visited node))))
      (p3/reference-note "alpha2020")
      (should (eq 'existing-node visited)))))

(ert-deftest p3-reference-note-creates-minimal-durable-org-file ()
  (let* ((directory (make-temp-file "p3-roam-" t))
         (org-roam-directory directory))
    (unwind-protect
        (cl-letf (((symbol-function 'require) (lambda (&rest _) t))
                  ((symbol-function 'org-roam-node-from-ref) (lambda (_ref) nil))
                  ((symbol-function 'org-id-new) (lambda () "note-id"))
                  ((symbol-function 'citar-get-value)
                   (lambda (field _key)
                     (pcase field
                       ("title" "Alpha Study")
                       ("author" "Ada Alpha")
                       ("year" "2020")))))
          (p3/reference-note "alpha2020")
          (let ((path (expand-file-name "alpha2020.org" directory)))
            (should (file-exists-p path))
            (with-temp-buffer
              (insert-file-contents path)
              (let ((text (buffer-string)))
                (should (string-match-p ":ROAM_REFS: @alpha2020" text))
                (should (string-match-p ":ID: note-id" text))
                (should (string-match-p "#+filetags: :literature:" text))
                (should-not (string-match-p "doi:" text))))))
      (delete-directory directory t))))
```

Add one more test that stubs finalization and proves `p3-inbox-*` becomes a mature key before any filename is chosen.

- [ ] **Step 2: Run focused tests and verify note cases red**

- [ ] **Step 3: Implement literature-note lookup/creation without citar-org-roam**

Use `org-roam-node-from-ref (concat "@" citekey)` to find an existing canonical reference node and `org-roam-node-visit` to open it. New notes use `<mature-citekey>.org` under `org-roam-directory`, `org-id-new`, `ROAM_REFS`, `:literature:`, and a human-readable title derived through Citar field getters. Do not recreate citar-org-roam variables or templates.

- [ ] **Step 4: Add complete project-registry tests**

Define a fixture containing a narrative citation and registry citation:

```elisp
(defconst p3-reference-test--project-org
  "#+title: Example\n#+filetags: :project:\n\nA narrative [cite:@narrative2020] mention.\n\n* References\n\n[cite:@alpha2020]\n")

(ert-deftest p3-reference-project-citekeys-ignore-narrative-citations ()
  (let ((file (make-temp-file "p3-project-" nil ".org"
                              p3-reference-test--project-org)))
    (unwind-protect
        (cl-letf (((symbol-function 'p3/reference--project-file)
                   (lambda (_node) file)))
          (should (equal '("alpha2020")
                         (p3/reference-project-citekeys 'project-node))))
      (delete-file file))))

(ert-deftest p3-reference-project-association-is-idempotent ()
  (let ((file (make-temp-file "p3-project-" nil ".org"
                              p3-reference-test--project-org)))
    (unwind-protect
        (cl-letf (((symbol-function 'p3/reference--project-file)
                   (lambda (_node) file)))
          (p3/reference-associate-project "beta2021" 'project-node)
          (p3/reference-associate-project "beta2021" 'project-node)
          (with-temp-buffer
            (insert-file-contents file)
            (should (= 1 (how-many "\\[cite:@beta2021\\]"
                                   (point-min) (point-max))))))
      (delete-file file))))
```

Also add complete tests that:

- create `* References` at level 1 when absent and store `[cite:@key]` on its own line;
- remove only a registry line while leaving the narrative citation intact;
- reject a target whose `org-roam-node-tags` lacks `project`;
- finalize a provisional key before association;
- call `p3/reference-find` with exactly the registry keys from `p3/reference-project-references`.

- [ ] **Step 5: Run focused tests and verify project cases red**

- [ ] **Step 6: Implement project selection and registry mutation using Org structure**

Use the public Org-roam interfaces:

```elisp
(defun p3/reference--project-node-p (node)
  (member "project" (org-roam-node-tags node)))

(defun p3/reference--current-project-node ()
  (when (and (derived-mode-p 'org-mode)
             (require 'org-roam nil t))
    (let ((node (org-roam-node-at-point)))
      (and node (p3/reference--project-node-p node) node))))

(defun p3/reference--select-project-node ()
  (unless (require 'org-roam nil t)
    (user-error "Org-roam is unavailable"))
  (org-roam-node-read nil #'p3/reference--project-node-p nil t))
```

Within the selected project file, use Org parsing to find a level-1 headline whose raw value is exactly `References`. Parse `citation-reference` elements only inside that subtree and read each `:key`. Add/remove only standalone registry lines in that subtree; never infer project membership from the rest of the note.

- [ ] **Step 7: Implement the classification dispatcher and extend the central action menu**

`p3/reference-classify` offers exactly:

```text
Add topic/status keyword
Remove topic/status keyword
Associate with project
Remove project association
```

The first two call Task 2 keyword helpers; the latter two mutate project-note registries. Extend `p3/reference--action-alist` with `Open/create literature note` and `Classify / project association`. `p3/reference-project-references` reuses `p3/reference-find` with the registry key list.

- [ ] **Step 8: Run focused tests and verify Task 5 green**

- [ ] **Step 9: Commit Task 5**

```bash
git add lisp/p3-reference.el test/p3-reference-test.el
git commit -m "Add reference notes and project associations"
```

---

### Task 6: PDF convention and declarative reference configuration

**Files:**
- Modify: `lisp/p3-reference.el`
- Modify: `test/p3-reference-test.el`
- Create: `lisp/p3-config-reference.el`
- Create: `test/p3-config-reference-test.el`

**Interfaces:**
- Consumes: Tasks 1–5 behavior.
- Produces:
  - `p3/reference-pdf-path (citekey) -> absolute path`
  - `p3/reference-attach-pdf (source-file &optional citekey)`
  - `p3/reference-open-pdf (&optional citekey)`
  - `p3/reference-command-map` with `a f i n p t r`
  - config-owned `p3/reference-bibliography-file` default `~/org/bib/main.bib`
  - config-owned `p3/reference-pdf-directory` default `~/org/lib/`
  - feature `p3-config-reference`

- [ ] **Step 1: Add complete PDF-path/laziness tests**

```elisp
(ert-deftest p3-reference-pdf-path-uses-mature-key-directory ()
  (let ((p3/reference-pdf-directory "/tmp/papers/"))
    (should (equal "/tmp/papers/alpha2020/main.pdf"
                   (p3/reference-pdf-path "alpha2020")))
    (should-error (p3/reference-pdf-path "p3-inbox-1"))))

(ert-deftest p3-reference-load-does-not-require-pdf-tools ()
  (should-not (featurep 'pdf-tools)))

(ert-deftest p3-reference-open-pdf-falls-back-when-pdf-tools-unusable ()
  (let (opened message-text)
    (cl-letf (((symbol-function 'p3/reference-pdf-path)
               (lambda (_key) "/tmp/alpha.pdf"))
              ((symbol-function 'file-exists-p) (lambda (_file) t))
              ((symbol-function 'find-file) (lambda (file) (setq opened file)))
              ((symbol-function 'require)
               (lambda (feature &rest _)
                 (if (eq feature 'pdf-tools) nil t)))
              ((symbol-function 'message)
               (lambda (format-string &rest args)
                 (setq message-text (apply #'format format-string args)))))
      (p3/reference-open-pdf "alpha2020")
      (should (equal "/tmp/alpha.pdf" opened))
      (should (string-match-p "default PDF viewer" message-text)))))
```

Add an attachment test proving a provisional key is finalized before destination selection and an existing `main.pdf` is never overwritten without `y-or-n-p` approval.

- [ ] **Step 2: Run focused tests and verify PDF cases red**

- [ ] **Step 3: Implement deterministic manual attachment and lazy reading**

New attachments copy to `<p3/reference-pdf-directory>/<mature-key>/main.pdf`; create that directory only when attaching. Do not write absolute PDF paths into `references.bib`. `p3/reference-open-pdf` opens the file, then attempts `(require 'pdf-tools nil t)` only for that action. If pdf-tools is missing or `pdf-view-mode` signals because its native backend is unavailable, leave the PDF open with Emacs's default viewer and emit a local message. Never call `pdf-tools-install` automatically.

Add `Open PDF` to the central action menu.

- [ ] **Step 4: Add the complete config-owner test skeleton**

Create `test/p3-config-reference-test.el` with static/form-reading helpers matching the existing focused config tests, and complete assertions that:

```elisp
(ert-deftest p3-config-reference-defaults-preserve-current-user-data-roots ()
  (let ((contents (p3-config-reference-test--contents)))
    (should (string-match-p (regexp-quote "~/org/bib/main.bib") contents))
    (should (string-match-p (regexp-quote "~/org/lib/") contents))))

(ert-deftest p3-config-reference-loads-behavior-before-binding-prefix ()
  (let* ((contents (p3-config-reference-test--contents))
         (behavior (string-match (regexp-quote
                                  "(p3/config-load-module 'p3-reference)")
                                 contents))
         (binding (string-match (regexp-quote
                                 "(global-set-key (kbd \"C-c b\") p3/reference-command-map)")
                                contents)))
    (should behavior)
    (should binding)
    (should (< behavior binding))))

(ert-deftest p3-config-reference-pdf-tools-is-lazy-and-never-installs-backend ()
  (let ((contents (p3-config-reference-test--contents)))
    (should (string-match-p "(use-package pdf-tools" contents))
    (should-not (string-match-p "pdf-tools-install" contents))))
```

Also assert the owner configures Org-cite/Citar to the canonical bibliography, declares Biblio, and contains no citar-org-roam/RefTeX machinery.

- [ ] **Step 5: Run config test and verify red**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-reference-test.el \
  -f ert-run-tests-batch-and-exit
```

- [ ] **Step 6: Implement `p3-config-reference.el` and the reload-safe command map**

Define customization before loading behavior:

```elisp
(defcustom p3/reference-bibliography-file
  (expand-file-name "~/org/bib/main.bib")
  "Canonical personal BibLaTeX bibliography."
  :type 'file)

(defcustom p3/reference-pdf-directory
  (file-name-as-directory (expand-file-name "~/org/lib/"))
  "Root directory for citekey-organized reference PDFs."
  :type 'directory)

(p3/config-load-module 'p3-reference)
```

Keep `bibtex-dialect` set to `biblatex` and `bibtex-align-at-equal-sign` enabled because they serve the new plain-file workflow. Do not carry forward the old RefTeX settings or `bibtex-user-optional-fields` experiment.

Configure:

```elisp
(setq org-cite-global-bibliography (list p3/reference-bibliography-file)
      org-cite-insert-processor 'citar
      org-cite-follow-processor 'citar
      org-cite-activate-processor 'citar
      citar-bibliography (list p3/reference-bibliography-file))
```

Declare Citar deferred, Biblio deferred, and pdf-tools command/deferred only. After Biblio loads, add exactly one documented extended action:

```elisp
(add-to-list 'biblio-selection-mode-actions-alist
             '("Save/enrich in P3 library" . p3/reference-biblio-save))
```

In `p3-reference.el`, rebuild the prefix map on exact-source reload:

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

Bind it globally with `C-c b`. Do not add an `e` or attachment key in v1.

- [ ] **Step 7: Run behavior + config tests and verify Task 6 green**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-reference-test.el \
  -l test/p3-config-reference-test.el \
  -f ert-run-tests-batch-and-exit
```

- [ ] **Step 8: Commit Task 6**

```bash
git add lisp/p3-reference.el lisp/p3-config-reference.el \
  test/p3-reference-test.el test/p3-config-reference-test.el
git commit -m "Add reference configuration boundary"
```

---

### Task 7: Replace abandoned citation config and expose the workflow consistently

**Files:**
- Modify: `config.org`
- Modify: `lisp/p3-config-org-roam.el`
- Modify: `test/p3-config-org-roam-test.el`
- Modify: `lisp/p3-config-base.el`
- Modify: `lisp/p3-commands.el`
- Modify: `test/p3-config-test.el`
- Modify: `test/p3-commands-test.el`

**Interfaces:**
- Consumes: `p3-config-reference` from Task 6.
- Produces: one reference owner in literate orchestration; no old citation stack; discoverable Which-Key/atlas bindings.

- [ ] **Step 1: Add architecture tests for the new owner and old-config removal**

Update `test/p3-config-test.el` so `p3-config-org-source-loads-fourteen-config-modules` expects 14 owners including `p3-config-reference`. Add an ordering test that computes positions and asserts:

```elisp
(should (< editing reference))
(should (< reference completion))
(should (< completion ess))
(should (< ess org))
(should (< org roam))
(should (< roam present))
(should (< present project-config))
(should (< project-config python))
(should (< python terminal))
```

Add one complete cleanup assertion:

```elisp
(ert-deftest p3-config-reference-old-inline-citation-machinery-is-gone ()
  (let ((contents (p3-config-test--contents "config.org")))
    (dolist (needle '("(use-package citar"
                      "(use-package citar-org-roam"
                      "reftex-default-bibliography"
                      "reftex-cite-format"
                      "bib-files-directory"
                      "pdf-files-directory"))
      (should-not (string-match-p (regexp-quote needle) contents)))
    (should (string-match-p
             (regexp-quote "(p3/config-load-module 'p3-config-reference)")
             contents))))
```

- [ ] **Step 2: Add the Org-roam capture regression before changing its config**

Change `test/p3-config-org-roam-test.el` to expect only the existing default capture template and unchanged dailies template. Add:

```elisp
(ert-deftest p3-config-org-roam-has-no-citar-dependent-literature-template ()
  (let ((contents
         (with-temp-buffer
           (insert-file-contents
            (p3-config-org-roam-test--path "lisp/p3-config-org-roam.el"))
           (buffer-string))))
    (dolist (needle '("citar-org-roam-subdir" "citar-citekey"
                      "citar-date" "note-title"))
      (should-not (string-match-p (regexp-quote needle) contents)))))
```

- [ ] **Step 3: Run focused architecture tests and verify red**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-test.el \
  -l test/p3-config-org-roam-test.el \
  -f ert-run-tests-batch-and-exit
```

- [ ] **Step 4: Replace the old citation block and old literature capture template**

In `config.org`, replace the entire current `** Bibtex & citation-related` implementation with concise ownership prose plus:

```elisp
(p3/config-load-module 'p3-config-reference)
```

Keep it at the former citation subsystem position between Editing/Functions and Completion rather than reordering unrelated modules.

In `p3-config-org-roam.el`, remove only the `"n" "literature note"` template that depends on citar-org-roam variables. Preserve normal capture, dailies, bindings, display, and autosync.

- [ ] **Step 5: Add Which-Key and keybinding-atlas tests/labels**

In `p3-config-base.el`, add labels:

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

In `p3-commands.el`, remove `("C-c b" . "insert citation")` from the Org section and add a `References` section with the seven subcommands.

Extend `test/p3-commands-test.el` with a complete assertion that finds the `References` section and compares its cdr to:

```elisp
'(("C-c b a" . "add reference")
  ("C-c b f" . "find reference")
  ("C-c b i" . "insert citation")
  ("C-c b n" . "literature note")
  ("C-c b p" . "open reference PDF")
  ("C-c b t" . "classify / associate")
  ("C-c b r" . "project references"))
```

- [ ] **Step 6: Run all focused integration tests**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-reference-test.el \
  -l test/p3-config-reference-test.el \
  -l test/p3-config-org-roam-test.el \
  -l test/p3-config-test.el \
  -l test/p3-commands-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS; generated config contains 14 owners, `C-c b` is no longer direct `org-cite-insert`, and no RefTeX/citar-org-roam citation experiment remains.

- [ ] **Step 7: Commit Task 7**

```bash
git add config.org lisp/p3-config-org-roam.el lisp/p3-config-base.el \
  lisp/p3-commands.el test/p3-config-org-roam-test.el \
  test/p3-config-test.el test/p3-commands-test.el
git commit -m "Route citations through reference workflow"
```

---

### Task 8: Reconstruction regression, CI integration, and final review

**Files:**
- Modify: `test/p3-reference-test.el`
- Modify: `.github/workflows/emacs-tests.yml`
- Modify: `.github/workflows/windows-platform-tests.yml`

**Interfaces:**
- Consumes: complete v1 subsystem.
- Produces: proof of plain-file reconstructability plus bounded Ubuntu/Windows CI evidence.

- [ ] **Step 1: Add a complete package-independent reconstruction regression**

```elisp
(ert-deftest p3-reference-durable-state-is-reconstructable-from-bib-and-org ()
  (let* ((directory (make-temp-file "p3-reconstruct-" t))
         (bib (expand-file-name "references.bib" directory))
         (project (expand-file-name "project.org" directory))
         (note (expand-file-name "literature.org" directory)))
    (unwind-protect
        (progn
          (with-temp-file bib
            (insert "@article{alpha2020, title={Alpha Study}, author={Alpha, Ada}, year={2020}}\n"))
          (with-temp-file project
            (insert "#+title: Project\n#+filetags: :project:\n\n* References\n[cite:@alpha2020]\n"))
          (with-temp-file note
            (insert ":PROPERTIES:\n:ID: literature-alpha\n:ROAM_REFS: @alpha2020\n:END:\n#+title: Alpha Study\n#+filetags: :literature:\n"))
          (let ((p3/reference-bibliography-file bib))
            (should (p3/reference--entry-alist "alpha2020")))
          (with-temp-buffer
            (insert-file-contents project)
            (org-mode)
            (should (string-match-p (regexp-quote "[cite:@alpha2020]")
                                    (buffer-string))))
          (with-temp-buffer
            (insert-file-contents note)
            (should (string-match-p (regexp-quote ":ROAM_REFS: @alpha2020")
                                    (buffer-string)))))
      (delete-directory directory t))))
```

The test must not require Citar, Biblio, pdf-tools, Org-roam DB access, or any P3 cache. It verifies the three durable plain-file joins directly.

- [ ] **Step 2: Run the full local ERT suite before touching CI**

Use the current workflow's complete ERT command and add:

```text
test/p3-reference-test.el
test/p3-config-reference-test.el
```

Expected: zero unexpected failures. If the execution environment has no Emacs, record that environment limitation; do not compensate by turning full CI into an iterative diagnostic loop.

- [ ] **Step 3: Add Ubuntu compile, smoke, and full-suite coverage**

In `.github/workflows/emacs-tests.yml`:

- byte-compile `lisp/p3-reference.el` and `lisp/p3-config-reference.el`;
- add `Smoke-load Reference configuration boundary` using package stubs/no network/no real user files;
- add the two new test files to the full ERT command.

The smoke asserts `p3-config-reference` and `p3-reference` features, exact default roots, and that global `C-c b` is `p3/reference-command-map`. It must not invoke DOI/Crossref or pdf-tools native setup.

- [ ] **Step 4: Add Windows platform-neutral reference coverage**

In `.github/workflows/windows-platform-tests.yml`:

- add both new Lisp files and both test files to path filters;
- byte-compile `p3-reference.el` and `p3-config-reference.el` with external package macros stubbed the same way existing config-owner compilation is handled;
- include `p3-config-reference-test.el` and `p3-reference-test.el` in Windows architecture ERT;
- do not install/invoke pdf-tools native support.

Tests must use `make-temp-file`, `expand-file-name`, and `file-name-as-directory`; fix any Unix-only assumptions rather than excluding the test on Windows.

- [ ] **Step 5: Run the pre-push static acceptance scan**

Verify the branch contains:

```text
zero use-package citar-org-roam
zero reftex-default-bibliography/reftex-cite-format
zero mature-citekey rename command
zero generic webpage scraper
zero pdf-tools-install call
exactly one p3-config-reference orchestration call
14 p3-config-* owners
C-c b with exactly a/f/i/n/p/t/r
bibliography default ~/org/bib/main.bib
PDF root default ~/org/lib/
```

Inspect the diff to confirm workflow behavior is in `p3-reference.el`, package/config ownership is in `p3-config-reference.el`, and unrelated Org/Org-roam behavior did not move.

- [ ] **Step 6: Commit the reconstruction/CI gate**

```bash
git add test/p3-reference-test.el \
  .github/workflows/emacs-tests.yml \
  .github/workflows/windows-platform-tests.yml
git commit -m "Verify portable reference workflow"
```

- [ ] **Step 7: Push once and use the normal PR CI gate**

Expected final evidence:

```text
Ubuntu byte compilation: PASS
Ubuntu reference config smoke: PASS
Ubuntu full ERT: PASS, 0 unexpected
Windows platform/project tests: PASS
Windows reference/config architecture tests: PASS
```

If a workflow fails, inspect the exact failed step/log and form a root-cause hypothesis before changing code or rerunning CI. Do not add diagnostic workflows.

- [ ] **Step 8: Adversarially review the exact finished head**

Review specifically for data-loss risk, accidental citekey migration, enrichment creating duplicate identities, hidden package/cache state, project-registry/narrative-citation confusion, startup coupling to absent user data or pdf-tools, path assumptions, and any dependency outside v1 scope. Fix blockers/high findings test-first, rerun focused tests, and rerun the coherent CI gate only if the reviewed head changes in runtime-relevant ways. Do not merge without explicit user approval.

---

## Plan Self-Review

**Spec coverage:** Tasks 1–2 cover data integrity, provisional/mature identity, duplicates, keywords, and atomic mutation. Task 3 covers all approved capture modes and non-destructive enrichment without scraping. Task 4 covers global retrieval and native Org citation insertion. Task 5 covers literature notes, project associations, project-scoped retrieval, and classification. Task 6 covers PDF convention/laziness plus the declarative owner and stable prefix. Task 7 removes abandoned machinery and preserves Org-roam/config architecture. Task 8 covers reconstructability, both CI boundaries, and adversarial final review.

**Scope check:** No browser integration, PDF sync/acquisition, precise PDF annotation, external reference manager, mature-key migration, standalone bibliography UI, or extra completion/action package is planned.

**Interface consistency:** `p3-inbox-*` is the only provisional test throughout. Enrichment mutates the existing target record through `p3/reference-merge-bibtex`; it never imports a second record for that target. Mature-key finalization occurs before notes/projects/PDF paths/citations. Both global and project retrieval reuse `p3/reference-find`. `C-c b` exposes only `a/f/i/n/p/t/r`; explicit enrichment and manual PDF attachment remain available through `M-x` rather than expanding the approved prefix.

**Portability check:** Existing `~/org/bib/main.bib` and `~/org/lib/` roots remain defaults, avoiding an unapproved data migration. All file tests use temporary platform-neutral paths. pdf-tools native support is never required by startup or Windows CI.
