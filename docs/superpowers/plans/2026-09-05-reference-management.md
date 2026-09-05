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
- Produces: `p3/reference-provisional-key-p`, `p3/reference--new-provisional-key`, `p3/reference--bibliography-path`, `p3/reference--goto-entry`, `p3/reference--entry-alist`, `p3/reference--entry-keys-from-content`, `p3/reference--validate-content`, `p3/reference--transaction`.

- [ ] **Step 1: Write the test harness and failing provisional/bootstrap tests**

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

- [ ] **Step 2: Run red**

```bash
emacs -Q --batch -L lisp -l test/p3-reference-test.el -f ert-run-tests-batch-and-exit
```

Expected: FAIL because `p3-reference.el` does not exist.

- [ ] **Step 3: Implement the load-safe skeleton**

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

- [ ] **Step 4: Add failing integrity tests**

```elisp
(defconst p3-reference-test--two-entries
  "@article{alpha2020,\n  title = {Alpha},\n  doi = {10.1000/alpha}\n}\n\n% keep this comment exactly\n@article{beta2021,\n  title = {Beta}\n}\n")

(ert-deftest p3-reference-validation-rejects-duplicate-keys ()
  (should-error
   (p3/reference--validate-content
    "@article{x, title={A}}\n@book{x, title={B}}\n")))

(ert-deftest p3-reference-validation-rejects-malformed-bibtex ()
  (should-error
   (p3/reference--validate-content "@article{x, title={Unclosed}\n")))

(ert-deftest p3-reference-transaction-leaves-original-on-failure ()
  (p3-reference-test--with-library p3-reference-test--two-entries
    (let ((before (with-temp-buffer
                    (insert-file-contents p3/reference-bibliography-file)
                    (buffer-string))))
      (should-error
       (p3/reference--transaction
        (lambda ()
          (goto-char (point-max))
          (insert "\n@article{alpha2020, title={Duplicate}}\n"))))
      (with-temp-buffer
        (insert-file-contents p3/reference-bibliography-file)
        (should (equal before (buffer-string)))))))

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

- [ ] **Step 5: Run red for integrity helpers**

Use the focused command from Step 2. Expected: provisional tests PASS; integrity tests FAIL.

- [ ] **Step 6: Implement validated same-filesystem transactions**

```elisp
(defun p3/reference--bibliography-path ()
  (unless (and (stringp p3/reference-bibliography-file)
               (not (string-empty-p p3/reference-bibliography-file)))
    (user-error "Reference bibliography is not configured"))
  (expand-file-name p3/reference-bibliography-file))

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
    (setq temp (make-temp-file
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

Implement `p3/reference--goto-entry` as an anchored regexp over `@type{key,`/`@type(key,` with `regexp-quote` on the key. Implement `p3/reference--validate-content` by opening CONTENT in `bibtex-mode`, walking ordinary entry heads, calling `bibtex-parse-entry` for each, rejecting parser errors, excluding `string/preamble/comment`, and rejecting any duplicate key before the transaction writes the candidate.

- [ ] **Step 7: Run green and commit**

```bash
emacs -Q --batch -L lisp -l test/p3-reference-test.el -f ert-run-tests-batch-and-exit
git add lisp/p3-reference.el test/p3-reference-test.el
git commit -m "Add safe reference bibliography core"
```

---

### Task 2: Import, duplicate detection, classification fields, and finalization

**Files:**
- Modify: `lisp/p3-reference.el`
- Modify: `test/p3-reference-test.el`

**Interfaces:**
- Produces: `p3/reference-normalize-doi`, `p3/reference-normalize-url`, `p3/reference-import-bibtex`, `p3/reference-add-keyword`, `p3/reference-remove-keyword`, `p3/reference--propose-citekey`, `p3/reference-finalize`.

- [ ] **Step 1: Add failing normalization/duplicate tests**

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

- [ ] **Step 2: Run red**

- [ ] **Step 3: Implement canonical import/duplicate logic**

```elisp
(defun p3/reference-import-bibtex (bibtex)
  (let* ((incoming (p3/reference--parse-single-entry bibtex))
         (key (cdr (assoc "=key=" incoming)))
         (duplicate (p3/reference--strong-duplicate-key incoming)))
    (when (p3/reference-provisional-key-p key)
      (user-error "p3-inbox-* keys are reserved for URL-only captures"))
    (cond
     (duplicate duplicate)
     ((and (p3/reference--possible-title-duplicate-keys incoming)
           (not (y-or-n-p "Possible title duplicate; add as a distinct reference? ")))
      (user-error "Reference import cancelled"))
     (t
      (p3/reference--transaction
       (lambda ()
         (goto-char (point-max))
         (unless (bolp) (insert "\n"))
         (insert bibtex)
         (unless (bolp) (insert "\n"))))
      key))))
```

`p3/reference--strong-duplicate-key` reads the canonical file directly and compares normalized DOI first, normalized URL second. `p3/reference--possible-title-duplicate-keys` lowercases, collapses whitespace, removes punctuation, and compares equality only; do not introduce fuzzy thresholds.

- [ ] **Step 4: Add failing keyword/finalization tests**

```elisp
(ert-deftest p3-reference-status-inbox-is-not-technical-provisional-state ()
  (should-not (p3/reference-provisional-key-p "alpha2020")))

(ert-deftest p3-reference-keywords-are-entry-local-and-idempotent ()
  (p3-reference-test--with-library p3-reference-test--two-entries
    (p3/reference-add-keyword "alpha2020" "quantitative-methods")
    (p3/reference-add-keyword "alpha2020" "quantitative-methods")
    (let ((entry (p3/reference--entry-alist "alpha2020")))
      (should (equal "quantitative-methods"
                     (cdr (assoc "keywords" entry)))))
    (should (equal "Beta"
                   (cdr (assoc "title"
                               (p3/reference--entry-alist "beta2021")))))))

(ert-deftest p3-reference-finalize-leaves-mature-key-unchanged ()
  (p3-reference-test--with-library "@article{alpha2020, title={Alpha}}\n"
    (should (equal "alpha2020" (p3/reference-finalize "alpha2020")))))

(ert-deftest p3-reference-finalize-needs-usable-generated-key ()
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

(ert-deftest p3-reference-finalize-rejects-colliding-key ()
  (p3-reference-test--with-library
      "@article{p3-inbox-1, title={Alpha}}\n@article{alpha2020, title={Existing}}\n"
    (cl-letf (((symbol-function 'p3/reference--propose-citekey)
               (lambda (_key) "alpha2020"))
              ((symbol-function 'read-string)
               (lambda (&rest _) "alpha2020")))
      (should-error (p3/reference-finalize "p3-inbox-1")))))
```

- [ ] **Step 5: Implement entry-local keyword mutation and finalization**

Use `bibtex-set-field` only after `p3/reference--goto-entry`. Split keywords on commas, trim/de-duplicate, and leave all other entry text alone.

```elisp
(defun p3/reference-finalize (citekey)
  (if (not (p3/reference-provisional-key-p citekey))
      citekey
    (let ((proposal (p3/reference--propose-citekey citekey)))
      (unless (and proposal (not (string-empty-p proposal)))
        (user-error "Reference needs more metadata before finalization"))
      (let ((accepted (read-string "Permanent citekey: " proposal)))
        (when (or (string-empty-p accepted)
                  (p3/reference-provisional-key-p accepted)
                  (p3/reference--entry-alist accepted))
          (user-error "Permanent citekey is invalid or already used"))
        (p3/reference--rename-provisional-entry-head citekey accepted)
        accepted))))
```

`p3/reference--propose-citekey` isolates the entry in a temporary BibTeX buffer and calls built-in `bibtex-generate-autokey`. `p3/reference--rename-provisional-entry-head` is private and refuses mature source keys. No public mature-key rename command exists.

- [ ] **Step 6: Run green and commit**

```bash
emacs -Q --batch -L lisp -l test/p3-reference-test.el -f ert-run-tests-batch-and-exit
git add lisp/p3-reference.el test/p3-reference-test.el
git commit -m "Add reference import and finalization"
```

---

### Task 3: Capture and non-destructive enrichment through Biblio

**Files:**
- Modify: `lisp/p3-reference.el`
- Modify: `test/p3-reference-test.el`

**Interfaces:**
- Produces: `p3/reference-add`, `p3/reference--input-kind`, `p3/reference--doi-in-string`, `p3/reference--capture-url`, `p3/reference-merge-bibtex`, buffer-local `p3/reference--biblio-target-key`, `p3/reference-biblio-save`, `p3/reference-enrich`.

- [ ] **Step 1: Add failing routing/offline-capture tests**

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

- [ ] **Step 2: Implement local input routing**

```elisp
(defun p3/reference-add (&optional input)
  (interactive)
  (let ((input (or input (read-string "Reference (DOI, URL, BibTeX, or search): "))))
    (pcase (p3/reference--input-kind input)
      ('bibtex (p3/reference-import-bibtex input))
      ('doi    (p3/reference--lookup-doi input))
      ('url    (p3/reference--capture-url input))
      ('search (p3/reference--lookup-title input)))))
```

A URL without a directly recognizable DOI appends one `@online{p3-inbox-..., ...}` with `url`, current `urldate`, and `keywords={status/inbox}`. It does not retrieve the webpage.

- [ ] **Step 3: Add failing acquisition/enrichment tests with Biblio stubs**

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

(ert-deftest p3-reference-enrichment-fills-blanks-without-changing-key ()
  (p3-reference-test--with-library
      "@article{p3-inbox-1, title={Alpha}, year={}}\n"
    (p3/reference-merge-bibtex
     "p3-inbox-1"
     "@article{remote, title={Alpha}, year={2024}, doi={10.1000/alpha}}")
    (let ((entry (p3/reference--entry-alist "p3-inbox-1")))
      (should (equal "2024" (cdr (assoc "year" entry))))
      (should (equal "10.1000/alpha" (cdr (assoc "doi" entry)))))))

(ert-deftest p3-reference-enrichment-preserves-declined-conflict ()
  (p3-reference-test--with-library
      "@article{p3-inbox-1, title={My corrected title}, year={2024}}\n"
    (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) nil)))
      (p3/reference-merge-bibtex
       "p3-inbox-1"
       "@article{remote, title={Remote title}, year={2024}}"))
    (should (equal "My corrected title"
                   (cdr (assoc "title"
                               (p3/reference--entry-alist "p3-inbox-1")))))))

(ert-deftest p3-reference-biblio-action-enriches-target-not-new-identity ()
  (p3-reference-test--with-library
      "@article{p3-inbox-1, title={Alpha}}\n"
    (let ((p3/reference--biblio-target-key "p3-inbox-1"))
      (cl-letf (((symbol-function 'biblio-format-bibtex)
                 (lambda (text _autokey) text)))
        (p3/reference-biblio-save
         `((backend . ,(lambda (command metadata callback)
                         (ignore metadata)
                         (when (eq command 'forward-bibtex)
                           (funcall callback
                                    "@article{remote, title={Alpha}, year={2024}}"))))))))
    (should (p3/reference--entry-alist "p3-inbox-1"))
    (should-not (p3/reference--entry-alist "remote"))))
```

- [ ] **Step 4: Implement Biblio's public backend integration and target-aware merge**

```elisp
(defvar-local p3/reference--biblio-target-key nil)

(defun p3/reference-biblio-save (metadata)
  (let ((target p3/reference--biblio-target-key)
        (backend (alist-get 'backend metadata)))
    (funcall
     backend 'forward-bibtex metadata
     (lambda (raw)
       (let ((bibtex (biblio-format-bibtex raw nil)))
         (if target
             (p3/reference-merge-bibtex target bibtex)
           (p3/reference-import-bibtex bibtex)))))))
```

DOI lookup lazily requires `biblio-doi` and calls `biblio-doi-forward-bibtex`; text lookup lazily requires `biblio-crossref` and calls `biblio-crossref-lookup` with the original text. `p3/reference-merge-bibtex` ignores the remote `=key=` and `=type=` identity, fills missing fields automatically, leaves equal values unchanged, and prompts before replacing any populated conflicting field. All entry changes use Task 1's transaction.

`p3/reference-enrich` uses DOI directly when present. Otherwise call `biblio-crossref-lookup` with the target title, or URL only when title is absent, and set `p3/reference--biblio-target-key` buffer-locally in the returned results buffer. Keep this as an `M-x` command; no `C-c b e` in v1.

- [ ] **Step 5: Run green and commit**

```bash
emacs -Q --batch -L lisp -l test/p3-reference-test.el -f ert-run-tests-batch-and-exit
git add lisp/p3-reference.el test/p3-reference-test.el
git commit -m "Add reference capture and enrichment"
```

---

### Task 4: Citar retrieval and native Org citation insertion

**Files:**
- Modify: `lisp/p3-reference.el`
- Modify: `test/p3-reference-test.el`

**Interfaces:**
- Produces: `p3/reference--select-key`, `p3/reference-find`, `p3/reference-insert-citation`, `p3/reference-open-url`, `p3/reference-edit-entry`, `p3/reference--action-alist`.

- [ ] **Step 1: Add failing Citar-wrapper/citation tests**

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

(ert-deftest p3-reference-empty-project-set-never-searches-globally ()
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

(ert-deftest p3-reference-insert-citation-finalizes-provisional-first ()
  (let (inserted)
    (cl-letf (((symbol-function 'require) (lambda (&rest _) t))
              ((symbol-function 'p3/reference-finalize)
               (lambda (_key) "alpha2020"))
              ((symbol-function 'citar-insert-citation)
               (lambda (keys &optional _arg) (setq inserted keys))))
      (p3/reference-insert-citation "p3-inbox-1")
      (should (equal '("alpha2020") inserted)))))

(ert-deftest p3-reference-insert-citation-skips-finalization-for-mature-key ()
  (let (inserted)
    (cl-letf (((symbol-function 'require) (lambda (&rest _) t))
              ((symbol-function 'p3/reference-finalize)
               (lambda (_key) (ert-fail "Mature key must not be finalized")))
              ((symbol-function 'citar-insert-citation)
               (lambda (keys &optional _arg) (setq inserted keys))))
      (p3/reference-insert-citation "alpha2020")
      (should (equal '("alpha2020") inserted)))))
```

- [ ] **Step 2: Implement one selector and one P3 action menu**

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

`p3/reference--select-key` lazily requires Citar. Nil `allowed-keys` means global; an explicitly empty list is a no-results error; a non-empty list passes a `:filter` predicate to `citar-select-ref`. Start the action alist with `Insert citation`, `Open URL`, and `Edit bibliography entry`; later tasks extend the same alist rather than creating another action system.

`p3/reference-insert-citation` finalizes only `p3-inbox-*` keys and then calls `citar-insert-citation` with the final key list. Do not construct Org citation strings manually.

- [ ] **Step 3: Run green and commit**

```bash
emacs -Q --batch -L lisp -l test/p3-reference-test.el -f ert-run-tests-batch-and-exit
git add lisp/p3-reference.el test/p3-reference-test.el
git commit -m "Add reference retrieval and citation actions"
```

---

### Task 5: Literature notes and canonical project-reference registries

**Files:**
- Modify: `lisp/p3-reference.el`
- Modify: `test/p3-reference-test.el`

**Interfaces:**
- Produces: `p3/reference-note`, `p3/reference--project-node-p`, `p3/reference--current-project-node`, `p3/reference--select-project-node`, `p3/reference-project-citekeys`, `p3/reference-associate-project`, `p3/reference-remove-project-association`, `p3/reference-project-references`, `p3/reference-classify`.

- [ ] **Step 1: Add failing literature-note tests**

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

(ert-deftest p3-reference-note-finalizes-before-choosing-file-name ()
  (let* ((directory (make-temp-file "p3-roam-" t))
         (org-roam-directory directory))
    (unwind-protect
        (cl-letf (((symbol-function 'require) (lambda (&rest _) t))
                  ((symbol-function 'p3/reference-finalize)
                   (lambda (_key) "alpha2020"))
                  ((symbol-function 'org-roam-node-from-ref) (lambda (_ref) nil))
                  ((symbol-function 'org-id-new) (lambda () "note-id"))
                  ((symbol-function 'citar-get-value)
                   (lambda (field _key)
                     (if (equal field "title") "Alpha Study" nil))))
          (p3/reference-note "p3-inbox-1")
          (should (file-exists-p (expand-file-name "alpha2020.org" directory)))
          (should-not (file-exists-p (expand-file-name "p3-inbox-1.org" directory))))
      (delete-directory directory t))))

(ert-deftest p3-reference-note-creates-minimal-durable-org-file ()
  (let* ((directory (make-temp-file "p3-roam-" t))
         (org-roam-directory directory))
    (unwind-protect
        (cl-letf (((symbol-function 'require) (lambda (&rest _) t))
                  ((symbol-function 'org-roam-node-from-ref) (lambda (_ref) nil))
                  ((symbol-function 'org-id-new) (lambda () "note-id"))
                  ((symbol-function 'citar-get-value)
                   (lambda (field _key)
                     (if (equal field "title") "Alpha Study" nil))))
          (p3/reference-note "alpha2020")
          (with-temp-buffer
            (insert-file-contents (expand-file-name "alpha2020.org" directory))
            (let ((text (buffer-string)))
              (should (string-match-p ":ROAM_REFS: @alpha2020" text))
              (should (string-match-p ":ID: note-id" text))
              (should (string-match-p "#+filetags: :literature:" text))
              (should (string-match-p "#+title: Alpha Study" text))
              (should-not (string-match-p "doi:" text)))))
      (delete-directory directory t))))
```

- [ ] **Step 2: Implement note lookup/creation without citar-org-roam**

Use `org-roam-node-from-ref (concat "@" mature-key)` and `org-roam-node-visit` for existing notes. New notes use `<mature-key>.org` under `org-roam-directory`, `org-id-new`, `ROAM_REFS`, `:literature:`, and a title from Citar. Do not copy whole bibliography metadata into the note.

- [ ] **Step 3: Add failing project-registry tests**

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

(ert-deftest p3-reference-project-association-creates-registry-and-is-idempotent ()
  (let ((file (make-temp-file "p3-project-" nil ".org"
                              "#+title: Example\n#+filetags: :project:\n")))
    (unwind-protect
        (cl-letf (((symbol-function 'p3/reference--project-file)
                   (lambda (_node) file))
                  ((symbol-function 'p3/reference--project-node-p)
                   (lambda (_node) t)))
          (p3/reference-associate-project "beta2021" 'project-node)
          (p3/reference-associate-project "beta2021" 'project-node)
          (with-temp-buffer
            (insert-file-contents file)
            (should (= 1 (how-many "^\\* References$" (point-min) (point-max))))
            (should (= 1 (how-many "\\[cite:@beta2021\\]"
                                   (point-min) (point-max))))))
      (delete-file file))))

(ert-deftest p3-reference-project-removal-does-not-touch-narrative-citation ()
  (let ((file (make-temp-file "p3-project-" nil ".org"
                              p3-reference-test--project-org)))
    (unwind-protect
        (cl-letf (((symbol-function 'p3/reference--project-file)
                   (lambda (_node) file))
                  ((symbol-function 'p3/reference--project-node-p)
                   (lambda (_node) t)))
          (p3/reference-remove-project-association "alpha2020" 'project-node)
          (with-temp-buffer
            (insert-file-contents file)
            (should (search-forward "[cite:@narrative2020]" nil t))
            (should-not (search-forward "[cite:@alpha2020]" nil t))))
      (delete-file file))))

(ert-deftest p3-reference-project-target-must-have-project-tag ()
  (cl-letf (((symbol-function 'org-roam-node-tags)
             (lambda (_node) '("idea"))))
    (should-not (p3/reference--project-node-p 'node))))

(ert-deftest p3-reference-project-association-finalizes-provisional-first ()
  (let (associated-key)
    (cl-letf (((symbol-function 'p3/reference-finalize)
               (lambda (_key) "alpha2020"))
              ((symbol-function 'p3/reference--associate-mature-key)
               (lambda (key _node) (setq associated-key key))))
      (p3/reference-associate-project "p3-inbox-1" 'project-node)
      (should (equal "alpha2020" associated-key)))))

(ert-deftest p3-reference-project-retrieval-reuses-global-find-ui ()
  (let (allowed)
    (cl-letf (((symbol-function 'p3/reference-project-citekeys)
               (lambda (_node) '("alpha2020" "beta2021")))
              ((symbol-function 'p3/reference-find)
               (lambda (keys) (setq allowed keys))))
      (p3/reference-project-references 'project-node)
      (should (equal '("alpha2020" "beta2021") allowed)))))
```

- [ ] **Step 4: Implement project selection and registry mutation**

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

Use Org parsing to find only a level-1 `References` headline. Parse `citation-reference` elements only inside that subtree. Add/remove standalone `[cite:@key]` registry lines only there. `p3/reference-associate-project` finalizes provisional keys before delegating to a private mature-key association helper.

`p3/reference-classify` offers exactly four actions: add topic/status keyword, remove topic/status keyword, associate with project, remove project association. Extend `p3/reference--action-alist` with `Open/create literature note` and `Classify / project association`; project retrieval reuses `p3/reference-find` with its allowed-key list.

- [ ] **Step 5: Run green and commit**

```bash
emacs -Q --batch -L lisp -l test/p3-reference-test.el -f ert-run-tests-batch-and-exit
git add lisp/p3-reference.el test/p3-reference-test.el
git commit -m "Add reference notes and project associations"
```

---

### Task 6: PDF convention and declarative reference owner

**Files:**
- Modify: `lisp/p3-reference.el`
- Modify: `test/p3-reference-test.el`
- Create: `lisp/p3-config-reference.el`
- Create: `test/p3-config-reference-test.el`

**Interfaces:**
- Produces: `p3/reference-pdf-path`, `p3/reference-attach-pdf`, `p3/reference-open-pdf`, reload-safe `p3/reference-command-map`, config-owned bibliography/PDF roots, `p3-config-reference`.

- [ ] **Step 1: Add failing PDF tests**

```elisp
(ert-deftest p3-reference-pdf-path-uses-mature-key-directory ()
  (let ((p3/reference-pdf-directory "/tmp/papers/"))
    (should (equal "/tmp/papers/alpha2020/main.pdf"
                   (p3/reference-pdf-path "alpha2020")))
    (should-error (p3/reference-pdf-path "p3-inbox-1"))))

(ert-deftest p3-reference-attach-pdf-finalizes-before-destination ()
  (p3-reference-test--with-library
      "@article{p3-inbox-1, title={Alpha}}\n"
    (let* ((source (expand-file-name "source.pdf" directory))
           destination)
      (with-temp-file source (insert "pdf"))
      (cl-letf (((symbol-function 'p3/reference-finalize)
                 (lambda (_key) "alpha2020"))
                ((symbol-function 'copy-file)
                 (lambda (_source target &rest _) (setq destination target))))
        (p3/reference-attach-pdf source "p3-inbox-1")
        (should (string-suffix-p "alpha2020/main.pdf" destination))))))

(ert-deftest p3-reference-attach-pdf-never-silently-overwrites ()
  (p3-reference-test--with-library "@article{alpha2020, title={Alpha}}\n"
    (let* ((source (expand-file-name "source.pdf" directory))
           (target (expand-file-name "alpha2020/main.pdf"
                                     p3/reference-pdf-directory)))
      (make-directory (file-name-directory target) t)
      (with-temp-file source (insert "new"))
      (with-temp-file target (insert "old"))
      (cl-letf (((symbol-function 'y-or-n-p) (lambda (&rest _) nil)))
        (should-error (p3/reference-attach-pdf source "alpha2020")))
      (with-temp-buffer
        (insert-file-contents target)
        (should (equal "old" (buffer-string)))))))

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

- [ ] **Step 2: Implement deterministic manual attachments and lazy reading**

```elisp
(defun p3/reference-pdf-path (citekey)
  (when (p3/reference-provisional-key-p citekey)
    (user-error "Finalize the reference before assigning a PDF path"))
  (expand-file-name "main.pdf"
                    (expand-file-name citekey
                                      (file-name-as-directory
                                       p3/reference-pdf-directory))))
```

`p3/reference-attach-pdf` finalizes first, creates only the mature-key directory, prompts before replacing an existing `main.pdf`, and copies the file. It does not write attachment paths to BibLaTeX. `p3/reference-open-pdf` calls `find-file`, then attempts `(require 'pdf-tools nil t)` and `pdf-view-mode`; missing/broken pdf-tools leaves the default Emacs PDF viewer active and only emits a message. Never call `pdf-tools-install` automatically. Add `Open PDF` to the common action alist.

- [ ] **Step 3: Add failing config-owner tests**

```elisp
;;; p3-config-reference-test.el --- Reference config boundary tests -*- lexical-binding: t; -*-
(require 'ert)
(require 'subr-x)

(defconst p3-config-reference-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(defun p3-config-reference-test--contents ()
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name "lisp/p3-config-reference.el"
                       p3-config-reference-test--root))
    (buffer-string)))

(ert-deftest p3-config-reference-preserves-current-data-roots ()
  (let ((contents (p3-config-reference-test--contents)))
    (should (string-match-p (regexp-quote "~/org/bib/main.bib") contents))
    (should (string-match-p (regexp-quote "~/org/lib/") contents))))

(ert-deftest p3-config-reference-loads-behavior-before-prefix-binding ()
  (let* ((contents (p3-config-reference-test--contents))
         (behavior (string-match
                    (regexp-quote "(p3/config-load-module 'p3-reference)")
                    contents))
         (binding (string-match
                   (regexp-quote
                    "(global-set-key (kbd \"C-c b\") p3/reference-command-map)")
                   contents)))
    (should behavior)
    (should binding)
    (should (< behavior binding))))

(ert-deftest p3-config-reference-wires-org-cite-citar-and-biblio ()
  (let ((contents (p3-config-reference-test--contents)))
    (dolist (needle '("org-cite-global-bibliography"
                      "org-cite-insert-processor 'citar"
                      "org-cite-follow-processor 'citar"
                      "org-cite-activate-processor 'citar"
                      "citar-bibliography"
                      "(use-package biblio"
                      "Save/enrich in P3 library"))
      (should (string-match-p (regexp-quote needle) contents)))))

(ert-deftest p3-config-reference-pdf-tools-is-lazy-and-never-installs-backend ()
  (let ((contents (p3-config-reference-test--contents)))
    (should (string-match-p "(use-package pdf-tools" contents))
    (should-not (string-match-p "pdf-tools-install" contents))))

(ert-deftest p3-config-reference-has-no-old-citation-stack ()
  (let ((contents (p3-config-reference-test--contents)))
    (dolist (needle '("citar-org-roam" "reftex-default-bibliography"
                      "reftex-cite-format" "bib-files-directory"))
      (should-not (string-match-p (regexp-quote needle) contents)))))
```

- [ ] **Step 4: Implement `p3-config-reference.el` and reload-safe command map**

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

(setq bibtex-dialect 'biblatex
      bibtex-align-at-equal-sign t
      org-cite-global-bibliography (list p3/reference-bibliography-file)
      org-cite-insert-processor 'citar
      org-cite-follow-processor 'citar
      org-cite-activate-processor 'citar
      citar-bibliography (list p3/reference-bibliography-file))
```

Declare Citar deferred, Biblio deferred, and pdf-tools command/deferred only. After Biblio loads:

```elisp
(add-to-list 'biblio-selection-mode-actions-alist
             '("Save/enrich in P3 library" . p3/reference-biblio-save))
```

In `p3-reference.el`:

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

Bind `(global-set-key (kbd "C-c b") p3/reference-command-map)`. Do not add an enrichment or attachment key in v1.

- [ ] **Step 5: Run green and commit**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-reference-test.el \
  -l test/p3-config-reference-test.el \
  -f ert-run-tests-batch-and-exit
git add lisp/p3-reference.el lisp/p3-config-reference.el \
  test/p3-reference-test.el test/p3-config-reference-test.el
git commit -m "Add reference configuration boundary"
```

---

### Task 7: Replace abandoned citation configuration and expose the workflow

**Files:**
- Modify: `config.org`
- Modify: `lisp/p3-config-org-roam.el`
- Modify: `test/p3-config-org-roam-test.el`
- Modify: `lisp/p3-config-base.el`
- Modify: `lisp/p3-commands.el`
- Modify: `test/p3-config-test.el`
- Modify: `test/p3-commands-test.el`

- [ ] **Step 1: Add failing config-orchestration cleanup tests**

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

Rename/update the existing owner-count test to require exactly 14 config modules including `p3-config-reference`. Extend the ordering test with `reference` and assert `editing < reference < completion`, leaving all later relative subsystem order unchanged.

- [ ] **Step 2: Add failing Org-roam capture cleanup test**

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

Adjust the existing capture-template expectation to contain only the default capture template; leave dailies unchanged.

- [ ] **Step 3: Replace inline citation stack and old literature template**

In `config.org`, replace the current `** Bibtex & citation-related` implementation with concise ownership prose and:

```elisp
(p3/config-load-module 'p3-config-reference)
```

Keep this at the former citation subsystem position. In `p3-config-org-roam.el`, remove only the citar-org-roam-dependent `"n" "literature note"` capture template.

- [ ] **Step 4: Add Which-Key and atlas discoverability with exact test**

Add Which-Key labels:

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

Remove `("C-c b" . "insert citation")` from the Org atlas section. Add a `References` section. In `test/p3-commands-test.el` assert:

```elisp
(ert-deftest p3-commands-atlas-describes-reference-prefix ()
  (let ((section (assoc "References" p3/keybinding-sections)))
    (should
     (equal
      (cdr section)
      '(("C-c b a" . "add reference")
        ("C-c b f" . "find reference")
        ("C-c b i" . "insert citation")
        ("C-c b n" . "literature note")
        ("C-c b p" . "open reference PDF")
        ("C-c b t" . "classify / associate")
        ("C-c b r" . "project references"))))))
```

- [ ] **Step 5: Run focused integration tests and commit**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-reference-test.el \
  -l test/p3-config-reference-test.el \
  -l test/p3-config-org-roam-test.el \
  -l test/p3-config-test.el \
  -l test/p3-commands-test.el \
  -f ert-run-tests-batch-and-exit
git add config.org lisp/p3-config-org-roam.el lisp/p3-config-base.el \
  lisp/p3-commands.el test/p3-config-org-roam-test.el \
  test/p3-config-test.el test/p3-commands-test.el
git commit -m "Route citations through reference workflow"
```

---

### Task 8: Plain-file reconstruction regression, CI integration, and adversarial review

**Files:**
- Modify: `test/p3-reference-test.el`
- Modify: `.github/workflows/emacs-tests.yml`
- Modify: `.github/workflows/windows-platform-tests.yml`

- [ ] **Step 1: Add package-independent reconstruction test**

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
            (should (string-match-p (regexp-quote "[cite:@alpha2020]")
                                    (buffer-string))))
          (with-temp-buffer
            (insert-file-contents note)
            (should (string-match-p (regexp-quote ":ROAM_REFS: @alpha2020")
                                    (buffer-string)))))
      (delete-directory directory t))))
```

This test must not require Citar, Biblio, pdf-tools, an Org-roam DB, or P3 private cache state.

- [ ] **Step 2: Run the full local ERT suite before CI edits**

Use the existing full ERT command from `.github/workflows/emacs-tests.yml` and add:

```text
test/p3-reference-test.el
test/p3-config-reference-test.el
```

Expected: zero unexpected failures. If the execution environment lacks Emacs, record that limitation and do not replace local diagnosis with repeated full CI runs.

- [ ] **Step 3: Add Ubuntu compile/smoke/full-suite coverage**

Add `lisp/p3-reference.el` and `lisp/p3-config-reference.el` to byte compilation. Add a `Smoke-load Reference configuration boundary` step that stubs external package features, never contacts the network, never touches real user files, and asserts:

```elisp
(and (featurep 'p3-config-reference)
     (featurep 'p3-reference)
     (equal p3/reference-bibliography-file
            (expand-file-name "~/org/bib/main.bib"))
     (equal p3/reference-pdf-directory
            (file-name-as-directory (expand-file-name "~/org/lib/")))
     (eq (lookup-key global-map (kbd "C-c b"))
         p3/reference-command-map))
```

Add both new test files to the full Ubuntu ERT command. Do not initialize pdf-tools native support.

- [ ] **Step 4: Add Windows platform-neutral coverage**

Add the two new Lisp files and two new test files to `pull_request.paths`. Byte-compile `p3-reference.el` and `p3-config-reference.el` using the same external-package macro stubbing pattern as existing config-owner compilation. Add `p3-reference-test.el` and `p3-config-reference-test.el` to the Windows architecture ERT command. Do not install/invoke pdf-tools native support. Fix any path test with `make-temp-file`/`expand-file-name`; do not skip it merely because Windows differs.

- [ ] **Step 5: Run the pre-push static acceptance scan**

Confirm exactly:

```text
zero use-package citar-org-roam
zero reftex-default-bibliography/reftex-cite-format
zero mature-citekey rename command
zero generic webpage scraper
zero pdf-tools-install call
exactly one p3-config-reference orchestration call
14 p3-config-* owners
C-c b with a/f/i/n/p/t/r and no extra v1 subcommands
bibliography default ~/org/bib/main.bib
PDF root default ~/org/lib/
```

Inspect the diff to confirm workflow behavior is in `p3-reference.el`, package/config ownership is in `p3-config-reference.el`, and unrelated Org/Org-roam behavior did not move.

- [ ] **Step 6: Commit, push once, and use the normal PR CI gate**

```bash
git add test/p3-reference-test.el \
  .github/workflows/emacs-tests.yml \
  .github/workflows/windows-platform-tests.yml
git commit -m "Verify portable reference workflow"
git push -u origin HEAD
```

Expected final evidence:

```text
Ubuntu byte compilation: PASS
Ubuntu reference config smoke: PASS
Ubuntu full ERT: PASS with 0 unexpected failures
Windows platform/project tests: PASS
Windows reference/config architecture tests: PASS
```

If a workflow fails, inspect the exact failed step/log and establish a root-cause hypothesis before changing code or rerunning CI. Do not add diagnostic workflows.

- [ ] **Step 7: Adversarially review the exact finished head**

Review for data-loss risk, accidental mature-key changes, enrichment creating duplicate identities, hidden package/cache state, project-registry versus narrative-citation confusion, startup coupling to absent user data or pdf-tools, platform-specific path assumptions, and any dependency outside v1 scope. Fix blockers/high findings test-first. Rerun focused tests after each fix and rerun the coherent CI gate only if the reviewed head changes in runtime-relevant ways. Do not merge without explicit user approval.

---

## Plan Self-Review

**Spec coverage:** Task 1 covers atomic storage and reconstructable BibLaTeX identity. Task 2 covers import, duplicates, global classification fields, provisional/mature state, and immutable mature keys. Task 3 covers all approved capture modes and target-aware non-destructive enrichment without scraping. Task 4 covers one global retrieval/action model and native Org citation insertion. Task 5 covers literature notes, canonical project associations, project-scoped retrieval, and classification. Task 6 covers deterministic PDF storage/reading plus declarative ownership and the stable prefix. Task 7 removes abandoned machinery and preserves the rest of Org-roam/config behavior. Task 8 proves plain-file reconstructability and adds bounded Ubuntu/Windows verification.

**Placeholder scan:** No `TBD`, `TODO`, `implement later`, omitted test body, or `Similar to Task` instruction remains. Test-writing steps include concrete ERT bodies; implementation steps include the exact public interfaces and code shape required by their tests.

**Interface consistency:** `p3-inbox-*` is the only provisional test throughout. Enrichment mutates an explicit target through `p3/reference-merge-bibtex`; it cannot import a second identity for that target. Finalization occurs before citations, literature-note filenames, project associations, and PDF paths. Global and project retrieval reuse `p3/reference-find`. `C-c b` exposes only `a/f/i/n/p/t/r`; enrichment and manual PDF attachment remain available via `M-x` rather than expanding the approved prefix.

**Portability check:** Existing `~/org/bib/main.bib` and `~/org/lib/` roots remain defaults, avoiding an unapproved data migration. File tests use platform-neutral temporary paths. pdf-tools native support is not needed for startup or Windows CI.
