# Org Configuration Boundaries Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract Org core, Org-roam, and Org presentation configuration from `config.org` into three focused configuration modules and three reusable behavior libraries without changing user-facing behavior or startup ordering.

**Architecture:** `config.org` remains the explicit top-level map and loads `p3-config-org`, `p3-config-org-roam`, and `p3-config-org-present` in their current broad positions. Each configuration module owns declarative package wiring and exact-source loads its new behavior library; `p3-org-export.el` remains unchanged and retains its existing `use-package` activation/reload semantics.

**Tech Stack:** Emacs Lisp, Org, Org Agenda, Org Babel, Org-roam, org-present, `use-package`, ERT, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-04-org-config-boundaries-design.md`

## Global Constraints

- Preserve behavior exactly; this is a structural refactor only.
- Do not reorganize Citar, `citar-org-roam`, BibTeX, RefTeX, LaTeX, Poly-R, Projectile, completion, or window management.
- Preserve Org -> Org-roam -> Poly-R -> Presentation broad ordering in `config.org`.
- Preserve every existing Org, Roam, and presentation keybinding, hook, template, path, and setting.
- Preserve Babel languages exactly: Emacs Lisp, R, C, Python, LaTeX, and shell.
- Preserve `org-confirm-babel-evaluate t`.
- Preserve the anonymous timestamp-on-save hook as an anonymous hook; do not normalize or deduplicate it.
- Preserve legacy function names, including `org-set-line-checkbox`, `org-roam-generate-tagged-header`, `org-roam-node-insert-immediate-with-tag`, and `org-roam-rg-search`.
- Preserve the current trailing `#` in the nonblank tagged-header output.
- `p3-org-export.el` must not change and must not gain exact-source reload semantics.
- `p3-org-present.el` directly requires built-in `face-remap`.
- Optional Org-roam/presentation packages must not be installed merely for byte compilation or smoke loading.
- No broad `display-buffer-alist` policy or other window-management changes.
- Keep CI economical: no iterative diagnostic workflows; use targeted tests and one final PR CI cycle after local/static verification.

---

## File Map

### New behavior libraries

- `lisp/p3-org.el` — reusable core Org commands only.
- `lisp/p3-org-roam.el` — reusable Org-roam helper/search/agenda behavior only.
- `lisp/p3-org-present.el` — stateful presentation behavior and direct `face-remap` dependency.

### New configuration modules

- `lisp/p3-config-org.el` — Org core, Babel, TODO, Agenda, PDF handling, and existing `p3-org-export` activation.
- `lisp/p3-config-org-roam.el` — Org-roam package settings, templates, bindings, and autosync.
- `lisp/p3-config-org-present.el` — hide-mode-line, visual-fill-column, org-present package wiring, bindings, hooks, and text scale.

### New focused tests

- `test/p3-org-test.el`
- `test/p3-config-org-test.el`
- `test/p3-org-roam-test.el`
- `test/p3-config-org-roam-test.el`
- `test/p3-org-present-test.el`
- `test/p3-config-org-present-test.el`

### Existing files to modify

- `config.org` — replace only the current Org, Org-roam, and Presentation implementation blocks with concise module-loader stanzas; leave intervening/out-of-scope sections in place.
- `test/p3-config-test.el` — update module ownership/count/order assertions and moved-code exclusions.
- `.github/workflows/emacs-tests.yml` — compile six new Lisp files, load six focused test files, and add three runtime smoke checks.
- `.github/workflows/windows-platform-tests.yml` — add source-level architecture/config-boundary coverage and matching path triggers only; do not install optional packages.

### Existing files that must remain unchanged

- `lisp/p3-org-export.el`
- `test/p3-org-export-test.el`

---

### Task 1: Extract Org core behavior and declarative configuration

**Files:**
- Create: `lisp/p3-org.el`
- Create: `lisp/p3-config-org.el`
- Create: `test/p3-org-test.el`
- Create: `test/p3-config-org-test.el`

**Interfaces:**
- Consumes: `p3/config-load-module` from `p3-config-loader.el`; built-in Org functions at runtime; existing `p3-org-export` feature through unchanged `use-package` activation.
- Produces: `p3/org-sort-todos`, `org-set-line-checkbox`, feature `p3-org`, feature `p3-config-org`.

- [ ] **Step 1: Write failing core behavior tests before creating `p3-org.el`**

Create `test/p3-org-test.el` with a repository-root/load-path setup matching the existing test files, then define tests that stub the Org entry points instead of requiring package configuration.

Use this shape for TODO sorting:

```elisp
(ert-deftest p3-org-sort-todos-preserves-current-org-sort-call ()
  (let (seen)
    (cl-letf (((symbol-function 'org-sort-entries)
               (lambda (&rest args) (setq seen args))))
      (p3/org-sort-todos)
      (should (equal seen '(nil 111))))))
```

`111` is the character code for `?o`; if the implementation/test uses `?o` directly, the assertion may use `'(nil ?o)`.

For checkbox behavior, cover both no-region and active-region semantics using temporary buffers. Pin the literal inserted prefix `"- [ ] "`, the number of affected lines, and the final cursor at the beginning of the last processed line as the current function does.

- [ ] **Step 2: Verify the focused behavior tests fail because `p3-org.el` does not exist**

Run, when Emacs is available:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-org-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: FAIL/load error for missing `p3-org` or undefined extracted commands.

In the ChatGPT connector harness, where Emacs is unavailable locally, preserve this RED-before-GREEN commit ordering and defer executable confirmation to the final Actions gate rather than spending a standalone CI run.

- [ ] **Step 3: Create the minimal `p3-org.el` behavior library**

Move the two existing definitions without redesign:

```elisp
;;; p3-org.el --- Core Org workflow helpers -*- lexical-binding: t; -*-

(declare-function org-sort-entries "org" (&optional with-case sorting-type get-key-func compare-func property interactive?))

(defun p3/org-sort-todos ()
  "Sort sibling entries by TODO state without changing outline hierarchy.
Run this on a parent heading to sort its children; DONE entries follow active
TODO states according to `org-todo-keywords'."
  (interactive)
  (org-sort-entries nil ?o))

(defun org-set-line-checkbox (arg)
  (interactive "p")
  (let ((n (or arg 1)))
    (when (region-active-p)
      (setq n (count-lines (region-beginning)
                           (region-end)))
      (goto-char (region-beginning)))
    (dotimes (_i n)
      (beginning-of-line)
      (insert "- [ ] ")
      (forward-line))
    (beginning-of-line)))

(provide 'p3-org)

;;; p3-org.el ends here
```

Do not `(require 'org)` merely to define these functions. Add only compiler declarations actually needed by warnings-as-errors compilation.

- [ ] **Step 4: Run the core behavior tests and make only behavior-preserving corrections**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-org-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS.

- [ ] **Step 5: Write source-semantic tests for `p3-config-org.el` before creating it**

Create `test/p3-config-org-test.el` using the parsed-form helpers already established in `test/p3-config-python-test.el`: read top-level forms, find `use-package` forms, and inspect keyword sections.

Tests must pin at minimum:

```elisp
(p3/config-load-module 'p3-org)
```

before the command binding; the exact Babel language list:

```elisp
'((emacs-lisp . t)
  (R . t)
  (C . t)
  (python . t)
  (latex . t)
  (shell . t))
```

and these values:

```elisp
(setq org-startup-folded 'content)
(setq org-confirm-babel-evaluate t
      org-src-fontify-natively t
      org-src-tab-acts-natively t
      org-hide-emphasis-markers t
      org-ellipsis " ↴")
(setq org-todo-keywords
      '((sequence "TODO(t)" "WAIT(w)" "|" "DONE(d)"))
      org-todo-keyword-faces
      '(("WAIT" . "DarkOrange")))
(setq org-agenda-sorting-strategy '(priority-down))
```

Pin the existing Org hooks, `C-c s`, `C-c C-x C-o`, Linux Evince PDF association, and the anonymous timestamp hook body.

Also assert that the module retains unchanged exporter activation in substance:

```elisp
(use-package p3-org-export
  :ensure nil
  :demand t
  :config
  (p3-org-export-setup))
```

and assert there is **no** `(p3/config-load-module 'p3-org-export)` form.

- [ ] **Step 6: Verify the config-boundary tests fail because the new module does not exist**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-org-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: FAIL due to missing `lisp/p3-config-org.el`.

- [ ] **Step 7: Create `p3-config-org.el` by moving the current forms without normalization**

Start with:

```elisp
;;; p3-config-org.el --- Org configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'p3-config-loader)

(p3/config-load-module 'p3-org)
```

Then move the current executable Org forms in their current semantic order: `org-startup-folded`, anonymous timestamp hook, `use-package org`, `p3/org-sort-todos` binding, unchanged `use-package p3-org-export`, Linux Evince association, TODO keywords/faces, and `use-package org-agenda` sorting.

Do not move the earlier Citar/BibTeX/RefTeX block or the LaTeX block into this file.

End with:

```elisp
(provide 'p3-config-org)
```

- [ ] **Step 8: Run both focused Org test files**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-org-test.el \
  -l test/p3-config-org-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS.

- [ ] **Step 9: Commit the core Org extraction**

```bash
git add lisp/p3-org.el lisp/p3-config-org.el \
        test/p3-org-test.el test/p3-config-org-test.el
git commit -m "Extract Org core configuration boundary"
```

---

### Task 2: Extract Org-roam behavior and declarative configuration

**Files:**
- Create: `lisp/p3-org-roam.el`
- Create: `lisp/p3-config-org-roam.el`
- Create: `test/p3-org-roam-test.el`
- Create: `test/p3-config-org-roam-test.el`

**Interfaces:**
- Consumes: `p3/config-load-module`; Org-roam functions/variables at runtime; `consult-ripgrep`; `org-agenda`; `seq`; `subr-x`.
- Produces: `org-roam-generate-tagged-header`, `org-roam-node-insert-immediate-with-tag`, `org-roam-rg-search`, `p3/org-roam-filter-by-tag`, `p3/org-roam-list-notes`, `p3/org-roam-list-notes-by-tag`, `p3/org-roam-get-agenda`, feature `p3-org-roam`, feature `p3-config-org-roam`.

- [ ] **Step 1: Write failing Org-roam behavior tests with no real database**

Create `test/p3-org-roam-test.el`. Require only ERT/CL helpers and `p3-org-roam`; stub Org-roam functions.

Pin blank tagged-header output exactly:

```elisp
"#+title: ${title}\n#+category:${title}\n#+created: %U\n#+last_modified: %U\n"
```

Pin nonblank output exactly, including the current trailing `#`:

```elisp
"#+title: ${title}\n#+category:${title}\n#+filetags: work\n#+created: %U\n#+last_modified: %U\n#"
```

For list/filter tests, stub:

```elisp
org-roam-node-list
org-roam-node-file
org-roam-node-tags
```

using simple plist/alist nodes and `cl-letf`.

For `p3/org-roam-get-agenda`, stub `read-string`, the listing functions, and `org-agenda`; assert `org-agenda-files` receives all files for blank input and only tagged files for nonblank input.

For `org-roam-rg-search`, bind `org-roam-directory` to a sentinel path and stub `consult-ripgrep`; assert the exact directory argument is forwarded.

For immediate insertion, capture the dynamically bound `org-roam-capture-templates` inside a stubbed `org-roam-node-insert` call and assert `:immediate-finish t` is present.

- [ ] **Step 2: Verify Org-roam behavior tests fail before implementation**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-org-roam-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: FAIL/load error for missing `p3-org-roam`.

- [ ] **Step 3: Create `p3-org-roam.el` by moving the current helpers verbatim in behavior**

Use this dependency shape:

```elisp
;;; p3-org-roam.el --- Org-roam workflow helpers -*- lexical-binding: t; -*-

(require 'seq)
(require 'subr-x)

(defvar org-agenda-files)
(defvar org-roam-capture-templates)
(defvar org-roam-directory)

(declare-function consult-ripgrep "consult" (dir &optional initial))
(declare-function org-agenda "org-agenda" (&optional arg keys restriction))
(declare-function org-roam-node-file "org-roam-node" (node))
(declare-function org-roam-node-insert "org-roam-node" (&optional arg &rest args))
(declare-function org-roam-node-list "org-roam-node" ())
(declare-function org-roam-node-tags "org-roam-node" (node))
```

Then move the seven current helper functions unchanged, including the trailing `#` behavior.

Do not require `org-roam` solely to define the helpers.

- [ ] **Step 4: Run Org-roam behavior tests**

Run the focused file and expect PASS.

- [ ] **Step 5: Write failing source-semantic tests for the Org-roam config owner**

Create `test/p3-config-org-roam-test.el` using parsed top-level forms. Assert:

```elisp
(p3/config-load-module 'p3-org-roam)
```

occurs before `(use-package org-roam ...)`, and pin the current `:hook`, `:custom`, `:bind`, and `:config` values.

The test must compare the current default capture template, literature-note capture template, and dailies template structurally, including this target expression:

```elisp
(file+head
 "%(expand-file-name (or citar-org-roam-subdir \"\") org-roam-directory)/${citar-citekey}.org"
 "#+title: ${citar-citekey} (${citar-date}). ${note-title}.\n#+created: %U\n#+last_modified: %U\n\n")
```

Pin all existing bindings:

```text
C-c n l  org-roam-buffer-toggle
C-c n f  org-roam-node-find
C-c n g  org-roam-graph
C-c n i  org-roam-node-insert
C-c n c  org-roam-capture
C-c n n  org-roam-node-insert-immediate-with-tag
C-c n s  org-roam-rg-search
C-c n d  org-roam-dailies-goto-today
C-c n t  org-roam-dailies-capture-today
C-c n C-t org-roam-tag-add
C-c n a  p3/org-roam-get-agenda
```

Pin `(org-roam-db-autosync-mode)` and the current node display template.

- [ ] **Step 6: Create `p3-config-org-roam.el`**

Use:

```elisp
;;; p3-config-org-roam.el --- Org-roam configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'p3-config-loader)

(p3/config-load-module 'p3-org-roam)

(use-package org-roam
  ...current declaration moved without semantic edits...)

(provide 'p3-config-org-roam)
```

Keep `citar-org-roam` outside this file. Do not alter its existing earlier `:after (citar org-roam)` declaration.

- [ ] **Step 7: Run both focused Roam test files**

Run both and expect PASS without creating a real Roam database or touching `~/org/notes/roam/`.

- [ ] **Step 8: Commit the Roam extraction**

```bash
git add lisp/p3-org-roam.el lisp/p3-config-org-roam.el \
        test/p3-org-roam-test.el test/p3-config-org-roam-test.el
git commit -m "Extract Org-roam configuration boundary"
```

---

### Task 3: Extract presentation state behavior and package wiring

**Files:**
- Create: `lisp/p3-org-present.el`
- Create: `lisp/p3-config-org-present.el`
- Create: `test/p3-org-present-test.el`
- Create: `test/p3-config-org-present-test.el`

**Interfaces:**
- Consumes: built-in `face-remap`; runtime `org-present`, `visual-fill-column`, and `hide-mode-line` functions/variables supplied by packages.
- Produces: `p3/org-present--state`, `p3/org-present-start`, `p3/org-present-toggle-fullscreen`, `p3/org-present-hook`, `p3/org-present-quit-hook`, `p3/org-present-prev`, `p3/org-present-next`, feature `p3-org-present`, feature `p3-config-org-present`.

- [ ] **Step 1: Write failing presentation behavior tests before implementation**

Create `test/p3-org-present-test.el` and stub every optional-package function the behavior calls.

Tests must cover:

1. `p3/org-present-start` signals `user-error` outside Org-derived modes and delegates to `org-present` inside a stubbed Org context.
2. `p3/org-present-toggle-fullscreen` changes frame parameter `fullscreen` from nil to `fullboth` and back.
3. `p3/org-present-next` and `p3/org-present-prev` delegate exactly once.
4. `p3/org-present-hook` captures header line, line-number mode state, inline-image state, visual-fill state/settings, hide-mode-line state, and face-remap cookies; then applies width `90`, centered text, hide-mode-line, and face scales `1.5`, `1.2`, `1.1`.
5. `p3/org-present-quit-hook` calls `org-present-small`, restores each saved state, removes each remap cookie, and sets `p3/org-present--state` back to nil.

Use `cl-letf` stubs for:

```elisp
org-present
org-present-big
org-present-small
org-present-next
org-present-prev
org-display-inline-images
org-remove-inline-images
visual-fill-column-mode
hide-mode-line-mode
display-line-numbers-mode
face-remap-add-relative
face-remap-remove-relative
```

- [ ] **Step 2: Verify presentation behavior tests fail before `p3-org-present.el` exists**

Run focused ERT and expect FAIL/load error.

- [ ] **Step 3: Create `p3-org-present.el` with direct `face-remap` ownership**

Start with:

```elisp
;;; p3-org-present.el --- Org presentation behavior -*- lexical-binding: t; -*-

(require 'face-remap)

(defvar org-inline-image-overlays)
(defvar visual-fill-column-center-text)
(defvar visual-fill-column-width)

(declare-function hide-mode-line-mode "hide-mode-line" (&optional arg))
(declare-function org-display-inline-images "org" (&rest args))
(declare-function org-present "org-present" ())
(declare-function org-present-big "org-present" ())
(declare-function org-present-next "org-present" ())
(declare-function org-present-prev "org-present" ())
(declare-function org-present-small "org-present" ())
(declare-function org-remove-inline-images "org" ())
(declare-function visual-fill-column-mode "visual-fill-column" (&optional arg))
```

Then move the current state variable and six functions without semantic changes.

Do not add `use-package` or require `p3-config-org-present`.

- [ ] **Step 4: Run focused presentation behavior tests and correct only declaration/test harness issues**

Expected: PASS.

- [ ] **Step 5: Write failing source-semantic tests for `p3-config-org-present.el`**

Create `test/p3-config-org-present-test.el` and pin this effective top-level order:

```text
(use-package hide-mode-line ...)
(use-package visual-fill-column ...)
(p3/config-load-module 'p3-org-present)
(use-package org-present ...)
```

Assert there is no standalone `(require 'face-remap)` in the config owner; the behavior library owns it.

Pin `hide-mode-line :after (org-present)`, `org-present-text-scale 4`, both hooks, `C-c P`, and every `org-present-mode-keymap` binding:

```text
C-c C-j     p3/org-present-next
C-c C-k     p3/org-present-prev
SPC         p3/org-present-next
<backspace> p3/org-present-prev
n           p3/org-present-next
p           p3/org-present-prev
f           p3/org-present-toggle-fullscreen
q           org-present-quit
```

- [ ] **Step 6: Create `p3-config-org-present.el` with package wiring only**

Use:

```elisp
;;; p3-config-org-present.el --- Org presentation configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'p3-config-loader)

(use-package hide-mode-line
  :after (org-present))

(use-package visual-fill-column)

(p3/config-load-module 'p3-org-present)

(use-package org-present
  ...current bindings/hooks/config moved unchanged...)

(provide 'p3-config-org-present)
```

Add only compile-time declarations required by warnings-as-errors byte compilation.

- [ ] **Step 7: Run both focused presentation test files**

Expected: PASS.

- [ ] **Step 8: Commit the presentation extraction**

```bash
git add lisp/p3-org-present.el lisp/p3-config-org-present.el \
        test/p3-org-present-test.el test/p3-config-org-present-test.el
git commit -m "Extract Org presentation configuration boundary"
```

---

### Task 4: Route `config.org` through the three owners and harden architecture tests

**Files:**
- Modify: `config.org`
- Modify: `test/p3-config-test.el`

**Interfaces:**
- Consumes: features `p3-config-org`, `p3-config-org-roam`, `p3-config-org-present` from Tasks 1-3.
- Produces: one explicit loader stanza per new configuration owner, with existing out-of-scope sections retaining their positions.

- [ ] **Step 1: Add failing architecture assertions before editing `config.org`**

Update the config-module test to expect ten explicit configuration modules:

```elisp
'(p3-config-base
  p3-config-editing
  p3-config-completion
  p3-config-ess
  p3-config-org
  p3-config-org-roam
  p3-config-org-present
  p3-config-python
  p3-config-workspace
  p3-config-git)
```

Add a dedicated ordering test that locates these exact needles in `config.org`:

```elisp
"(p3/config-load-module 'p3-config-org)"
"(p3/config-load-module 'p3-config-org-roam)"
"(use-package poly-R"
"(p3/config-load-module 'p3-config-org-present)"
```

and asserts:

```elisp
(should (< org roam))
(should (< roam poly-r))
(should (< poly-r present))
```

Add ownership assertions that each loader stanza occurs exactly once and that the following moved definitions/forms no longer appear inline:

```text
(defun p3/org-sort-todos
(defun org-set-line-checkbox
(defun org-roam-generate-tagged-header
(defun org-roam-node-insert-immediate-with-tag
(defun org-roam-rg-search
(defun p3/org-roam-filter-by-tag
(defun p3/org-roam-list-notes
(defun p3/org-roam-list-notes-by-tag
(defun p3/org-roam-get-agenda
(defvar-local p3/org-present--state
(defun p3/org-present-start
(defun p3/org-present-toggle-fullscreen
(defun p3/org-present-hook
(defun p3/org-present-quit-hook
(defun p3/org-present-prev
(defun p3/org-present-next
(use-package org-roam
(use-package org-present
```

Do **not** forbid legitimate `(python . t)`, `(R . t)`, citation, LaTeX, or `citar-org-roam` references.

Assert `config.org` still contains the existing Citar/BibTeX/RefTeX section markers/forms, LaTeX forms, Poly-R declaration, and `(use-package citar-org-roam ...)`.

- [ ] **Step 2: Verify the new architecture assertions fail against the still-inline config**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: FAIL because the three loader stanzas are absent and inline implementation remains.

- [ ] **Step 3: Replace only the three approved implementation regions in `config.org`**

Replace the current Org implementation block with concise prose and:

```elisp
(p3/config-load-module 'p3-config-org)
```

Replace the current Org-roam implementation block with concise prose and:

```elisp
(p3/config-load-module 'p3-config-org-roam)
```

Leave the `** Poly-R` section exactly between Roam and Presentation.

Replace the current Presentation implementation block with concise prose and:

```elisp
(p3/config-load-module 'p3-config-org-present)
```

Do not move or rewrite the earlier citation/BibTeX/RefTeX or LaTeX sections.

Because connector updates replace whole files, reconstruct `config.org` from exact current branch contents, then reject any diff containing unrelated whitespace/content changes before committing.

- [ ] **Step 4: Update the older export-ownership architecture assertion without changing exporter semantics**

The existing test currently expects `(use-package p3-org-export` directly in `config.org`. Change it to assert:

```elisp
(p3/config-load-module 'p3-config-org)
```

in `config.org`, `(use-package p3-org-export` in `lisp/p3-config-org.el`, and absence of `p3/org-export-to-office` implementation from both top-level config and config module.

- [ ] **Step 5: Run architecture and all six focused Org boundary tests**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-test.el \
  -l test/p3-org-test.el \
  -l test/p3-config-org-test.el \
  -l test/p3-org-roam-test.el \
  -l test/p3-config-org-roam-test.el \
  -l test/p3-org-present-test.el \
  -l test/p3-config-org-present-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS.

- [ ] **Step 6: Confirm `p3-org-export.el` and its test are byte-for-byte unchanged**

Run:

```bash
git diff --exit-code master -- lisp/p3-org-export.el test/p3-org-export-test.el
```

Expected: no output, exit 0.

- [ ] **Step 7: Commit top-level orchestration**

```bash
git add config.org test/p3-config-test.el
git commit -m "Route Org subsystems through focused modules"
```

---

### Task 5: Add compile/runtime CI coverage and run the final regression gate

**Files:**
- Modify: `.github/workflows/emacs-tests.yml`
- Modify: `.github/workflows/windows-platform-tests.yml`

**Interfaces:**
- Consumes: all six new Lisp files and six new focused test files.
- Produces: warnings-as-errors compilation, three runtime-load smoke checks, Ubuntu full-suite coverage, and Windows source-level boundary coverage without optional-package installation.

- [ ] **Step 1: Add all six new Lisp files to Ubuntu warnings-as-errors byte compilation**

Add:

```text
lisp/p3-org.el
lisp/p3-config-org.el
lisp/p3-org-roam.el
lisp/p3-config-org-roam.el
lisp/p3-org-present.el
lisp/p3-config-org-present.el
```

to the existing `batch-byte-compile` list after package installation has already been suppressed with:

```elisp
(require 'use-package-ensure)
(setq use-package-ensure-function (lambda (&rest _) t))
```

Do not install Org-roam, org-present, hide-mode-line, or visual-fill-column for this compile step. Resolve warnings with declaration-only `defvar`/`declare-function` forms in the owning source files.

- [ ] **Step 2: Add an Org-core runtime smoke check**

Add a workflow step that loads `p3-config-loader.el` and `p3-config-org.el` with package installation suppressed, then exits nonzero unless:

```elisp
(featurep 'p3-config-org)
(featurep 'p3-org)
(equal org-startup-folded 'content)
(eq org-confirm-babel-evaluate t)
```

are all true.

Do not exact-source load `p3-org-export`; let the unchanged `use-package p3-org-export :demand t` form exercise its real activation path.

- [ ] **Step 3: Add an Org-roam config smoke test using stubs, not package installation**

Before loading `p3-config-org-roam.el`, provide the minimum package surface needed for the `use-package org-roam` declaration to evaluate without side effects. Use temporary symbols/maps/functions and `(provide 'org-roam)` / any required subfeatures rather than creating a database.

The assertion must at least verify:

```elisp
(featurep 'p3-config-org-roam)
(featurep 'p3-org-roam)
(equal org-roam-directory "~/org/notes/roam/")
```

and the smoke harness must stub `org-roam-db-autosync-mode` so no database is opened.

- [ ] **Step 4: Add a presentation config smoke test using stubs, not package installation**

Provide stub features/functions/maps for `hide-mode-line`, `visual-fill-column`, and `org-present`, including `org-mode-map` and `org-present-mode-keymap` where necessary for `use-package :bind` evaluation.

Load `p3-config-org-present.el` and assert:

```elisp
(featurep 'p3-config-org-present)
(featurep 'p3-org-present)
(featurep 'face-remap)
(equal org-present-text-scale 4)
```

Do not enter presentation mode or manipulate a real frame/buffer beyond what batch Emacs itself creates.

- [ ] **Step 5: Add all six focused tests to the Ubuntu full ERT invocation**

Load:

```text
test/p3-org-test.el
test/p3-config-org-test.el
test/p3-org-roam-test.el
test/p3-config-org-roam-test.el
test/p3-org-present-test.el
test/p3-config-org-present-test.el
```

Keep the existing `test/p3-org-export-test.el` line unchanged.

- [ ] **Step 6: Extend Windows path triggers and source-level test invocation only**

Add the three new config modules and three config-boundary test files to Windows workflow path triggers:

```text
lisp/p3-config-org.el
lisp/p3-config-org-roam.el
lisp/p3-config-org-present.el
test/p3-config-org-test.el
test/p3-config-org-roam-test.el
test/p3-config-org-present-test.el
```

Add the three config-boundary tests to the existing Windows config-architecture ERT command.

Do not add runtime Org-roam/presentation smoke checks on Windows and do not add behavior-library path triggers that would cause Windows jobs without corresponding Windows behavior coverage.

- [ ] **Step 7: Run static pre-PR verification before pushing the implementation head**

Confirm:

```bash
git diff --check master...HEAD
git diff --exit-code master -- lisp/p3-org-export.el test/p3-org-export-test.el
```

Inspect the aggregate `config.org` diff and reject any changes outside the Org, Org-roam, and Presentation regions.

Search the branch diff for `TBD`, `TODO` placeholders introduced by this work, accidental package-install commands, broad `display-buffer-alist` changes, or changes under citation/LaTeX/Poly-R/Projectile.

- [ ] **Step 8: Open/update the PR only after the implementation head is final enough for one CI cycle**

The PR summary must state that this is behavior-preserving decomposition and explicitly note:

- exporter implementation/reload behavior unchanged;
- trailing Roam header `#` intentionally preserved;
- direct `face-remap` dependency moved with presentation behavior;
- optional packages are stubbed rather than installed in smoke checks;
- Citar/BibTeX/RefTeX, LaTeX, and Poly-R are out of scope.

- [ ] **Step 9: Verify the final Ubuntu and Windows runs from the exact PR head**

Ubuntu must show:

- warnings-as-errors byte compilation success;
- Org core runtime smoke success;
- Org-roam stubbed runtime smoke success;
- presentation stubbed runtime smoke success;
- full ERT suite success with zero unexpected failures.

Windows must show:

- existing platform/project gate success;
- config architecture gate success including the three new source-level config-boundary tests.

If a run fails, inspect the exact job log and fix the root cause; do not add diagnostic workflows.

- [ ] **Step 10: Perform final adversarial review before any merge recommendation**

Review the aggregate PR against the spec for:

- any changed Org/Roam/presentation behavior;
- accidental exporter reload changes;
- missing direct dependencies in behavior libraries;
- package installation in compile/smoke steps;
- config ordering drift;
- capture/template/keybinding drift;
- presentation state restoration coverage;
- unrelated modifications.

Do not merge without explicit user approval.
