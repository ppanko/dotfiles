# Org Configuration Boundaries Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract Org core, Org-roam, and Org presentation configuration from `config.org` into three focused configuration modules and three reusable behavior libraries without changing user-facing behavior or startup ordering.

**Architecture:** `config.org` remains the explicit top-level map and loads `p3-config-org`, `p3-config-org-roam`, and `p3-config-org-present` in their current broad positions. Each new config module owns declarative wiring and exact-source loads only its new behavior library. `p3-org-export.el` remains unchanged and keeps its current `use-package` activation/reload semantics.

**Tech Stack:** Emacs Lisp, Org, Org Agenda, Org Babel, Org-roam, org-present, `use-package`, ERT, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-04-org-config-boundaries-design.md`

## Global Constraints

- Preserve behavior exactly; this is a structural refactor only.
- Do not reorganize Citar, `citar-org-roam`, BibTeX, RefTeX, LaTeX, Poly-R, Projectile, completion, or window management.
- Preserve Org -> Org-roam -> Poly-R -> Presentation broad ordering in `config.org`.
- Preserve every existing Org, Roam, and presentation keybinding, hook, template, path, and setting.
- Preserve Babel languages exactly: Emacs Lisp, R, C, Python, LaTeX, and shell.
- Preserve `org-confirm-babel-evaluate t`.
- Preserve the anonymous timestamp-on-save hook as anonymous; do not name, deduplicate, or otherwise normalize it.
- Preserve legacy command names, including `org-set-line-checkbox`, `org-roam-generate-tagged-header`, `org-roam-node-insert-immediate-with-tag`, and `org-roam-rg-search`.
- Preserve the current trailing `#` in the nonblank tagged-header output.
- `lisp/p3-org-export.el` and `test/p3-org-export-test.el` must remain byte-for-byte unchanged.
- `p3-org-export.el` must not gain exact-source reload semantics.
- `p3-org-present.el` directly requires built-in `face-remap`.
- Optional Org-roam/presentation packages must not be installed merely for compilation or smoke loading.
- No broad `display-buffer-alist` policy or other window-management change.
- Keep CI economical: no diagnostic workflows or iterative Actions loops; perform one final PR CI cycle once the implementation head is coherent.

---

## File Map

**Create behavior libraries**

- `lisp/p3-org.el` — reusable core Org commands.
- `lisp/p3-org-roam.el` — reusable Org-roam helper/search/agenda behavior.
- `lisp/p3-org-present.el` — stateful presentation behavior and direct `face-remap` dependency.

**Create configuration modules**

- `lisp/p3-config-org.el` — Org core, Babel, TODO, Agenda, PDF handling, and unchanged `p3-org-export` activation.
- `lisp/p3-config-org-roam.el` — Org-roam settings, capture templates, bindings, and autosync.
- `lisp/p3-config-org-present.el` — hide-mode-line, visual-fill-column, org-present bindings/hooks/config.

**Create focused tests**

- `test/p3-org-test.el`
- `test/p3-config-org-test.el`
- `test/p3-org-roam-test.el`
- `test/p3-config-org-roam-test.el`
- `test/p3-org-present-test.el`
- `test/p3-config-org-present-test.el`

**Modify**

- `config.org`
- `test/p3-config-test.el`
- `.github/workflows/emacs-tests.yml`
- `.github/workflows/windows-platform-tests.yml`

**Must not modify**

- `lisp/p3-org-export.el`
- `test/p3-org-export-test.el`

---

### Task 1: Extract Org core behavior and configuration

**Files:**
- Create: `lisp/p3-org.el`
- Create: `lisp/p3-config-org.el`
- Create: `test/p3-org-test.el`
- Create: `test/p3-config-org-test.el`

**Interfaces:**
- Consumes: `p3/config-load-module`, built-in Org APIs at runtime, existing `p3-org-export` through unchanged `use-package` activation.
- Produces: `p3/org-sort-todos`, `org-set-line-checkbox`, features `p3-org` and `p3-config-org`.

- [ ] **Step 1: Write failing behavior tests for the two extracted commands**

Create `test/p3-org-test.el` with the standard repository-root/load-path setup and:

```elisp
;;; p3-org-test.el --- Tests for p3-org -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)

(defconst p3-org-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(add-to-list 'load-path (expand-file-name "lisp" p3-org-test--root))
(require 'p3-org)

(ert-deftest p3-org-sort-todos-preserves-current-sort-call ()
  (let (seen)
    (cl-letf (((symbol-function 'org-sort-entries)
               (lambda (&rest args) (setq seen args))))
      (p3/org-sort-todos)
      (should (equal seen (list nil ?o))))))

(ert-deftest p3-org-set-line-checkbox-prefixes-current-line ()
  (with-temp-buffer
    (insert "alpha\nbeta\n")
    (goto-char (point-min))
    (org-set-line-checkbox 1)
    (should (equal (buffer-string) "- [ ] alpha\nbeta\n"))
    (should (= (point) (line-beginning-position)))))

(ert-deftest p3-org-set-line-checkbox-prefixes-active-region-lines ()
  (with-temp-buffer
    (transient-mark-mode 1)
    (insert "alpha\nbeta\ngamma\n")
    (goto-char (point-min))
    (push-mark (line-beginning-position 3) t t)
    (activate-mark)
    (org-set-line-checkbox 1)
    (should (equal (buffer-string)
                   "- [ ] alpha\n- [ ] beta\ngamma\n"))
    (should (looking-at "gamma"))))

(provide 'p3-org-test)
;;; p3-org-test.el ends here
```

- [ ] **Step 2: Verify RED before creating the behavior file**

Run when local Emacs is available:

```bash
emacs -Q --batch -L lisp -l test/p3-org-test.el -f ert-run-tests-batch-and-exit
```

Expected: load failure because `p3-org` does not exist. In the connector-only ChatGPT harness, preserve this test-first commit ordering and do not spend a standalone Actions run solely to demonstrate the expected missing-file failure.

- [ ] **Step 3: Create `lisp/p3-org.el` exactly as the behavior boundary**

```elisp
;;; p3-org.el --- Core Org workflow helpers -*- lexical-binding: t; -*-

(declare-function org-sort-entries
                  "org"
                  (&optional with-case sorting-type get-key-func compare-func
                             property interactive?))

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

Do not require Org merely to define these commands.

- [ ] **Step 4: Run the behavior tests**

```bash
emacs -Q --batch -L lisp -l test/p3-org-test.el -f ert-run-tests-batch-and-exit
```

Expected: PASS.

- [ ] **Step 5: Write failing source-semantic tests for `p3-config-org.el`**

Create `test/p3-config-org-test.el` using the parsed-form helper pattern from `test/p3-config-python-test.el`. The tests must assert all of the following exact facts:

1. `(p3/config-load-module 'p3-org)` exists before the binding of `p3/org-sort-todos`.
2. `org-startup-folded` is `content`.
3. The anonymous timestamp hook still sets:

```elisp
time-stamp-active t
time-stamp-start "#\\+last_modified:[ \t]*"
time-stamp-end "$"
time-stamp-format "\[%Y-%m-%d %3a %02H:%02M\]"
```

and locally adds `time-stamp` to `before-save-hook`.
4. The `use-package org` block preserves:

```elisp
:bind (:map org-mode-map
            ("C-c s" lambda () (interactive)
             (insert "#+BEGIN_SRC emacs-lisp\n#+END_SRC")))
:hook ((org-mode . flyspell-mode)
       (org-mode . visual-line-mode)
       (org-mode . org-indent-mode))
```

5. Babel languages are exactly:

```elisp
'((emacs-lisp . t)
  (R . t)
  (C . t)
  (python . t)
  (latex . t)
  (shell . t))
```

6. Org settings are exactly:

```elisp
(setq org-confirm-babel-evaluate t
      org-src-fontify-natively t
      org-src-tab-acts-natively t
      org-hide-emphasis-markers t
      org-ellipsis " ↴")
```

7. `C-c C-x C-o` binds `p3/org-sort-todos`.
8. The exporter activation is still:

```elisp
(use-package p3-org-export
  :ensure nil
  :demand t
  :config
  (p3-org-export-setup))
```

and there is no `(p3/config-load-module 'p3-org-export)`.
9. Linux PDF handling remains `(add-to-list 'org-file-apps '("pdf" . "evince %s"))`.
10. TODO state remains:

```elisp
(setq org-todo-keywords
      '((sequence "TODO(t)" "WAIT(w)" "|" "DONE(d)"))
      org-todo-keyword-faces
      '(("WAIT" . "DarkOrange")))
```

11. Org Agenda remains `(setq org-agenda-sorting-strategy '(priority-down))`.

- [ ] **Step 6: Verify the config tests are RED**

```bash
emacs -Q --batch -L lisp -l test/p3-config-org-test.el -f ert-run-tests-batch-and-exit
```

Expected: missing `lisp/p3-config-org.el`.

- [ ] **Step 7: Create `lisp/p3-config-org.el` with the complete moved configuration**

Use this implementation, preserving the current anonymous hook and exporter activation:

```elisp
;;; p3-config-org.el --- Org configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'p3-config-loader)

(defvar org-agenda-sorting-strategy)
(defvar org-confirm-babel-evaluate)
(defvar org-ellipsis)
(defvar org-file-apps)
(defvar org-hide-emphasis-markers)
(defvar org-mode-map)
(defvar org-src-fontify-natively)
(defvar org-src-tab-acts-natively)
(defvar org-startup-folded)
(defvar org-todo-keyword-faces)
(defvar org-todo-keywords)

(declare-function org-babel-do-load-languages "ob-core" (sym value))
(declare-function p3-org-export-setup "p3-org-export" ())

(p3/config-load-module 'p3-org)

(setq org-startup-folded 'content)

(add-hook 'org-mode-hook
          (lambda ()
            (setq-local time-stamp-active t
                        time-stamp-start "#\\+last_modified:[ \t]*"
                        time-stamp-end "$"
                        time-stamp-format "\[%Y-%m-%d %3a %02H:%02M\]")
            (add-hook 'before-save-hook 'time-stamp nil 'local)))

(use-package org
  :defer t
  :bind (:map org-mode-map
              ("C-c s" lambda () (interactive)
               (insert "#+BEGIN_SRC emacs-lisp\n#+END_SRC")))
  :hook ((org-mode . flyspell-mode)
         (org-mode . visual-line-mode)
         (org-mode . org-indent-mode))
  :init
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((emacs-lisp . t)
     (R . t)
     (C . t)
     (python . t)
     (latex . t)
     (shell . t)))
  :config
  (setq org-confirm-babel-evaluate t
        org-src-fontify-natively t
        org-src-tab-acts-natively t
        org-hide-emphasis-markers t
        org-ellipsis " ↴"))

(define-key org-mode-map (kbd "C-c C-x C-o") #'p3/org-sort-todos)

(use-package p3-org-export
  :ensure nil
  :demand t
  :config
  (p3-org-export-setup))

(when (eq system-type 'gnu/linux)
  (add-to-list 'org-file-apps '("pdf" . "evince %s")))

(setq org-todo-keywords
      '((sequence "TODO(t)" "WAIT(w)" "|" "DONE(d)"))
      org-todo-keyword-faces
      '(("WAIT" . "DarkOrange")))

(use-package org-agenda
  :ensure nil
  :config
  (setq org-agenda-sorting-strategy '(priority-down)))

(provide 'p3-config-org)
;;; p3-config-org.el ends here
```

If warnings-as-errors reports a compiler-only declaration mismatch, adjust only declarations/signatures; do not change executable forms.

- [ ] **Step 8: Run both focused Org test files**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-org-test.el \
  -l test/p3-config-org-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS.

- [ ] **Step 9: Commit Task 1**

```bash
git add lisp/p3-org.el lisp/p3-config-org.el test/p3-org-test.el test/p3-config-org-test.el
git commit -m "Extract Org core configuration boundary"
```

---

### Task 2: Extract Org-roam behavior and configuration

**Files:**
- Create: `lisp/p3-org-roam.el`
- Create: `lisp/p3-config-org-roam.el`
- Create: `test/p3-org-roam-test.el`
- Create: `test/p3-config-org-roam-test.el`

**Interfaces:**
- Consumes: `p3/config-load-module`; Org-roam APIs at runtime; `consult-ripgrep`; `org-agenda`; built-in `seq`/`subr-x`.
- Produces: `org-roam-generate-tagged-header`, `org-roam-node-insert-immediate-with-tag`, `org-roam-rg-search`, `p3/org-roam-filter-by-tag`, `p3/org-roam-list-notes`, `p3/org-roam-list-notes-by-tag`, `p3/org-roam-get-agenda`, features `p3-org-roam` and `p3-config-org-roam`.

- [ ] **Step 1: Write failing behavior tests that use stubs instead of a database**

Create `test/p3-org-roam-test.el`. Pin these two exact header outputs:

```elisp
"#+title: ${title}\n#+category:${title}\n#+created: %U\n#+last_modified: %U\n"
```

and, for tag `work`, including the trailing `#`:

```elisp
"#+title: ${title}\n#+category:${title}\n#+filetags: work\n#+created: %U\n#+last_modified: %U\n#"
```

Use `cl-letf` stubs for `read-string`, `org-roam-node-list`, `org-roam-node-file`, `org-roam-node-tags`, `org-roam-node-insert`, `consult-ripgrep`, and `org-agenda`. Assert:

- blank/nonblank tag predicates;
- all-note and tag-filtered file lists;
- `p3/org-roam-get-agenda` sets `org-agenda-files` correctly and calls `org-agenda`;
- `org-roam-rg-search` forwards `org-roam-directory` exactly;
- immediate insertion passes through its original args and dynamically supplies a one-entry tagged capture template whose plist contains `:immediate-finish t`.

- [ ] **Step 2: Verify RED before creating the behavior library**

```bash
emacs -Q --batch -L lisp -l test/p3-org-roam-test.el -f ert-run-tests-batch-and-exit
```

Expected: missing `p3-org-roam`.

- [ ] **Step 3: Create `lisp/p3-org-roam.el` with the complete moved helpers**

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

(defun org-roam-generate-tagged-header ()
  (let ((tag (read-string "Enter tag: ")))
    (if (string-empty-p tag)
        (concat "#+title: ${title}\n#+category:${title}\n#+created: %U\n#+last_modified: %U\n")
      (concat "#+title: ${title}\n#+category:${title}\n#+filetags: " tag
              "\n#+created: %U\n#+last_modified: %U\n#"))))

(defun org-roam-node-insert-immediate-with-tag (arg &rest args)
  (interactive "p")
  (let ((args (cons arg args))
        (org-roam-capture-templates
         (list
          (append
           (car
            '(("t" "tagged" plain "%?"
               :if-new
               (file+head "%<%Y%m%d%H%M%S>-${slug}.org"
                          org-roam-generate-tagged-header)
               :unnarrowed t)))
           '(:immediate-finish t)))))
    (apply #'org-roam-node-insert args)))

(defun org-roam-rg-search ()
  "Search org-roam directory using consult-ripgrep. With live-preview."
  (interactive)
  (consult-ripgrep org-roam-directory))

(defun p3/org-roam-filter-by-tag (tag-name)
  (lambda (node)
    (member tag-name (org-roam-node-tags node))))

(defun p3/org-roam-list-notes ()
  (mapcar #'org-roam-node-file
          (org-roam-node-list)))

(defun p3/org-roam-list-notes-by-tag (tag-name)
  (mapcar #'org-roam-node-file
          (seq-filter
           (p3/org-roam-filter-by-tag tag-name)
           (org-roam-node-list))))

(defun p3/org-roam-get-agenda ()
  (interactive)
  (let ((tag (read-string "Enter tag: ")))
    (if (string-empty-p tag)
        (setq org-agenda-files (p3/org-roam-list-notes))
      (setq org-agenda-files (p3/org-roam-list-notes-by-tag tag))))
  (org-agenda))

(provide 'p3-org-roam)
;;; p3-org-roam.el ends here
```

Do not require `org-roam` solely to define these helpers.

- [ ] **Step 4: Run the focused behavior tests**

```bash
emacs -Q --batch -L lisp -l test/p3-org-roam-test.el -f ert-run-tests-batch-and-exit
```

Expected: PASS.

- [ ] **Step 5: Write failing source-semantic tests for the Roam config owner**

Create `test/p3-config-org-roam-test.el` using parsed top-level forms. Assert `(p3/config-load-module 'p3-org-roam)` occurs before `(use-package org-roam ...)` and structurally compare these exact values:

```elisp
(org-roam-database-connector 'sqlite-builtin)
(org-roam-directory "~/org/notes/roam/")
(org-roam-completion-everywhere t)
(org-roam-completion-system 'default)
(org-roam-dailies-directory "journal/")
```

Pin the exact default capture template:

```elisp
'(("d" "default" plain "%?"
   :if-new (file+head "%<%Y%m%d%H%M%S>-${slug}.org"
                      "#+title: ${title}\n#+category:${title}\n#+created: %U\n#+last_modified: %U\n")
   :unnarrowed t)
```

plus the existing literature-note entry:

```elisp
("n" "literature note" plain "* Heading\n %?"
 :target
 (file+head
  "%(expand-file-name (or citar-org-roam-subdir \"\") org-roam-directory)/${citar-citekey}.org"
  "#+title: ${citar-citekey} (${citar-date}). ${note-title}.\n#+created: %U\n#+last_modified: %U\n\n")
 :unnarrowed t)
```

and dailies template:

```elisp
'(("d" "default" entry "* %<%I:%M %p>: %?"
   :target
   (file+head "%<%Y-%m-%d>.org"
              "#+title: %<%Y-%m-%d %a>\n#+created: %U\n#+last_modified: %U\n")))
```

Pin all bindings exactly:

```text
C-c n l   org-roam-buffer-toggle
C-c n f   org-roam-node-find
C-c n g   org-roam-graph
C-c n i   org-roam-node-insert
C-c n c   org-roam-capture
C-c n n   org-roam-node-insert-immediate-with-tag
C-c n s   org-roam-rg-search
C-c n d   org-roam-dailies-goto-today
C-c n t   org-roam-dailies-capture-today
C-c n C-t org-roam-tag-add
C-c n a   p3/org-roam-get-agenda
```

Also pin:

```elisp
(setq org-roam-node-display-template
      (concat "${title:*} "
              (propertize "${tags:10}" 'face 'org-tag)))
(org-roam-db-autosync-mode)
```

- [ ] **Step 6: Create `lisp/p3-config-org-roam.el` with the complete current declaration**

```elisp
;;; p3-config-org-roam.el --- Org-roam configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'p3-config-loader)

(defvar org-roam-node-display-template)

(declare-function org-roam-db-autosync-mode "org-roam-db" (&optional arg))

(p3/config-load-module 'p3-org-roam)

(use-package org-roam
  :hook
  (after-init . org-roam-mode)
  :custom
  (org-roam-database-connector 'sqlite-builtin)
  (org-roam-directory "~/org/notes/roam/")
  (org-roam-completion-everywhere t)
  (org-roam-completion-system 'default)
  (org-roam-capture-templates
   '(("d" "default" plain "%?"
      :if-new
      (file+head "%<%Y%m%d%H%M%S>-${slug}.org"
                 "#+title: ${title}\n#+category:${title}\n#+created: %U\n#+last_modified: %U\n")
      :unnarrowed t)
     ("n" "literature note" plain "* Heading\n %?"
      :target
      (file+head
       "%(expand-file-name (or citar-org-roam-subdir \"\") org-roam-directory)/${citar-citekey}.org"
       "#+title: ${citar-citekey} (${citar-date}). ${note-title}.\n#+created: %U\n#+last_modified: %U\n\n")
      :unnarrowed t)))
  (org-roam-dailies-directory "journal/")
  (org-roam-dailies-capture-templates
   '(("d" "default" entry "* %<%I:%M %p>: %?"
      :target
      (file+head "%<%Y-%m-%d>.org"
                 "#+title: %<%Y-%m-%d %a>\n#+created: %U\n#+last_modified: %U\n"))))
  :bind (("C-c n l" . org-roam-buffer-toggle)
         ("C-c n f" . org-roam-node-find)
         ("C-c n g" . org-roam-graph)
         ("C-c n i" . org-roam-node-insert)
         ("C-c n c" . org-roam-capture)
         ("C-c n n" . org-roam-node-insert-immediate-with-tag)
         ("C-c n s" . org-roam-rg-search)
         ("C-c n d" . org-roam-dailies-goto-today)
         ("C-c n t" . org-roam-dailies-capture-today)
         ("C-c n C-t" . org-roam-tag-add)
         ("C-c n a" . p3/org-roam-get-agenda))
  :config
  (setq org-roam-node-display-template
        (concat "${title:*} "
                (propertize "${tags:10}" 'face 'org-tag)))
  (org-roam-db-autosync-mode))

(provide 'p3-config-org-roam)
;;; p3-config-org-roam.el ends here
```

Keep the existing earlier `use-package citar-org-roam` block in `config.org`; do not move it into this module.

- [ ] **Step 7: Run both focused Roam test files**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-org-roam-test.el \
  -l test/p3-config-org-roam-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS without creating a real Roam database.

- [ ] **Step 8: Commit Task 2**

```bash
git add lisp/p3-org-roam.el lisp/p3-config-org-roam.el \
        test/p3-org-roam-test.el test/p3-config-org-roam-test.el
git commit -m "Extract Org-roam configuration boundary"
```

---

### Task 3: Extract presentation behavior and configuration

**Files:**
- Create: `lisp/p3-org-present.el`
- Create: `lisp/p3-config-org-present.el`
- Create: `test/p3-org-present-test.el`
- Create: `test/p3-config-org-present-test.el`

**Interfaces:**
- Consumes: built-in `face-remap`; optional `org-present`, `visual-fill-column`, and `hide-mode-line` APIs at runtime.
- Produces: `p3/org-present--state`, `p3/org-present-start`, `p3/org-present-toggle-fullscreen`, `p3/org-present-hook`, `p3/org-present-quit-hook`, `p3/org-present-prev`, `p3/org-present-next`, features `p3-org-present` and `p3-config-org-present`.

- [ ] **Step 1: Write failing behavior tests with all optional-package calls stubbed**

Create `test/p3-org-present-test.el`. Cover:

- `p3/org-present-start` rejects a non-Org buffer with `user-error` and calls `org-present` in an Org-derived-mode test buffer;
- fullscreen toggles nil -> `fullboth` -> nil by stubbing `frame-parameter`/`set-frame-parameter`;
- next/prev wrappers delegate once;
- enter hook stores header-line, line-number state, inline-image state, visual-fill state/settings, hide-mode-line state, and remap cookies, then applies line numbers off, `org-present-big`, inline images if absent, width `90`, centering `t`, visual-fill on, hide-mode-line on, and scale factors `1.5`, `1.2`, `1.1`;
- quit hook calls `org-present-small`, restores each prior state, removes every stored remap cookie, and clears `p3/org-present--state`.

Stub with `cl-letf`:

```text
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

- [ ] **Step 2: Verify RED before creating `p3-org-present.el`**

```bash
emacs -Q --batch -L lisp -l test/p3-org-present-test.el -f ert-run-tests-batch-and-exit
```

Expected: missing `p3-org-present`.

- [ ] **Step 3: Create `lisp/p3-org-present.el` with direct `face-remap` dependency and unchanged behavior**

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

(defvar-local p3/org-present--state nil
  "Saved buffer state while `org-present' is active.")

(defun p3/org-present-start ()
  "Start a presentation in the current Org buffer."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Presentation mode requires an Org buffer"))
  (org-present))

(defun p3/org-present-toggle-fullscreen ()
  "Toggle fullscreen for the current presentation frame."
  (interactive)
  (set-frame-parameter
   nil 'fullscreen
   (unless (frame-parameter nil 'fullscreen) 'fullboth)))

(defun p3/org-present-hook ()
  "Prepare the current Org buffer for presentation mode."
  (setq-local p3/org-present--state
              (list :header-line header-line-format
                    :line-numbers (bound-and-true-p display-line-numbers-mode)
                    :inline-images (and (boundp 'org-inline-image-overlays)
                                        org-inline-image-overlays)
                    :visual-fill (bound-and-true-p visual-fill-column-mode)
                    :visual-fill-width visual-fill-column-width
                    :visual-fill-center visual-fill-column-center-text
                    :hide-mode-line (bound-and-true-p hide-mode-line-mode)
                    :face-remap-cookies nil))
  (setq-local header-line-format " ")
  (display-line-numbers-mode -1)
  (org-present-big)
  (unless (and (boundp 'org-inline-image-overlays)
               org-inline-image-overlays)
    (org-display-inline-images))
  (setq-local visual-fill-column-width 90
              visual-fill-column-center-text t)
  (visual-fill-column-mode 1)
  (hide-mode-line-mode +1)
  (setf (plist-get p3/org-present--state :face-remap-cookies)
        (list (face-remap-add-relative 'org-level-1 :height 1.5)
              (face-remap-add-relative 'org-level-2 :height 1.2)
              (face-remap-add-relative 'org-level-3 :height 1.1))))

(defun p3/org-present-quit-hook ()
  "Restore the buffer state saved by `p3/org-present-hook'."
  (let ((state p3/org-present--state))
    (org-present-small)
    (when state
      (setq-local header-line-format (plist-get state :header-line))
      (if (plist-get state :line-numbers)
          (display-line-numbers-mode +1)
        (display-line-numbers-mode -1))
      (unless (plist-get state :inline-images)
        (org-remove-inline-images))
      (setq-local visual-fill-column-width
                  (plist-get state :visual-fill-width)
                  visual-fill-column-center-text
                  (plist-get state :visual-fill-center))
      (if (plist-get state :visual-fill)
          (visual-fill-column-mode +1)
        (visual-fill-column-mode -1))
      (if (plist-get state :hide-mode-line)
          (hide-mode-line-mode +1)
        (hide-mode-line-mode -1))
      (dolist (cookie (plist-get state :face-remap-cookies))
        (face-remap-remove-relative cookie)))
    (setq-local p3/org-present--state nil)))

(defun p3/org-present-prev ()
  "Move to the previous presentation slide."
  (interactive)
  (org-present-prev))

(defun p3/org-present-next ()
  "Move to the next presentation slide."
  (interactive)
  (org-present-next))

(provide 'p3-org-present)
;;; p3-org-present.el ends here
```

- [ ] **Step 4: Run focused presentation behavior tests**

```bash
emacs -Q --batch -L lisp -l test/p3-org-present-test.el -f ert-run-tests-batch-and-exit
```

Expected: PASS.

- [ ] **Step 5: Write failing source-semantic tests for the presentation config owner**

Create `test/p3-config-org-present-test.el`. Parse top-level forms and pin this effective order:

```text
(use-package hide-mode-line ...)
(use-package visual-fill-column ...)
(p3/config-load-module 'p3-org-present)
(use-package org-present ...)
```

Assert `p3-config-org-present.el` has no standalone `(require 'face-remap)` and `p3-org-present.el` does.

Pin `hide-mode-line :after (org-present)`, hooks:

```elisp
((org-present-mode . p3/org-present-hook)
 (org-present-mode-quit . p3/org-present-quit-hook))
```

`org-present-text-scale 4`, `C-c P`, and these map bindings:

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

- [ ] **Step 6: Create `lisp/p3-config-org-present.el` with exact package wiring**

```elisp
;;; p3-config-org-present.el --- Org presentation configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'p3-config-loader)

(defvar org-mode-map)
(defvar org-present-mode-keymap)
(defvar org-present-text-scale)

(use-package hide-mode-line
  :after (org-present))

(use-package visual-fill-column)

(p3/config-load-module 'p3-org-present)

(use-package org-present
  :bind ((:map org-mode-map
               ("C-c P" . p3/org-present-start))
         (:map org-present-mode-keymap
               ("C-c C-j" . p3/org-present-next)
               ("C-c C-k" . p3/org-present-prev)
               ("SPC" . p3/org-present-next)
               ("<backspace>" . p3/org-present-prev)
               ("n" . p3/org-present-next)
               ("p" . p3/org-present-prev)
               ("f" . p3/org-present-toggle-fullscreen)
               ("q" . org-present-quit)))
  :hook ((org-present-mode . p3/org-present-hook)
         (org-present-mode-quit . p3/org-present-quit-hook))
  :config
  (setq org-present-text-scale 4))

(provide 'p3-config-org-present)
;;; p3-config-org-present.el ends here
```

- [ ] **Step 7: Run both focused presentation test files**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-org-present-test.el \
  -l test/p3-config-org-present-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS.

- [ ] **Step 8: Commit Task 3**

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
- Consumes: `p3-config-org`, `p3-config-org-roam`, `p3-config-org-present`.
- Produces: one explicit top-level loader stanza per subsystem with current out-of-scope sections retaining their positions.

- [ ] **Step 1: Add failing architecture assertions before editing `config.org`**

Update the config-module ownership test to require all ten modules:

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

Add an ordering test locating:

```text
(p3/config-load-module 'p3-config-org)
(p3/config-load-module 'p3-config-org-roam)
(use-package poly-R
(p3/config-load-module 'p3-config-org-present)
```

and assert Org < Roam < Poly-R < Presentation.

Add one-owner assertions that each new loader occurs exactly once and that `config.org` no longer contains:

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

Do not forbid Babel `(python . t)` or `(R . t)` references. Assert `config.org` still contains `(use-package citar-org-roam`, the BibTeX/RefTeX setup, the LaTeX `org-latex-pdf-process`, and `(use-package poly-R`.

- [ ] **Step 2: Verify RED against the still-inline config**

```bash
emacs -Q --batch -L lisp -l test/p3-config-test.el -f ert-run-tests-batch-and-exit
```

Expected: FAIL because the three loader stanzas do not yet exist.

- [ ] **Step 3: Replace only the approved Org section with concise orchestration**

The `** org` section becomes:

```org
** org

Org core behavior lives in =lisp/p3-org.el=. Declarative Org, Babel, TODO,
Agenda, PDF-opening, and export-activation configuration lives in
=lisp/p3-config-org.el=.

#+BEGIN_SRC emacs-lisp
  (p3/config-load-module 'p3-config-org)
#+END_SRC
```

The separate `** org-agenda` implementation is absorbed into `p3-config-org.el`; do not leave a second inline Agenda owner.

- [ ] **Step 4: Replace only the approved Org-roam section**

Use:

```org
** org-roam

Org-roam package configuration lives in =lisp/p3-config-org-roam.el= and
reusable Roam search, capture, filtering, and agenda helpers live in
=lisp/p3-org-roam.el=.

#+BEGIN_SRC emacs-lisp
  (p3/config-load-module 'p3-config-org-roam)
#+END_SRC
```

Leave `** Poly-R` immediately after this section.

- [ ] **Step 5: Replace only the approved Presentation section**

Use:

```org
** Presentation

Org presentation package wiring lives in =lisp/p3-config-org-present.el=;
state capture/restoration and presentation commands live in
=lisp/p3-org-present.el=.

#+BEGIN_SRC emacs-lisp
  (p3/config-load-module 'p3-config-org-present)
#+END_SRC
```

Do not move Projectile/Python or any section around it.

- [ ] **Step 6: Update the existing export integration architecture test**

Change `p3-config-org-owns-org-export-integration` so it asserts:

- `config.org` contains `(p3/config-load-module 'p3-config-org)`;
- `lisp/p3-config-org.el` contains `(use-package p3-org-export`;
- neither file contains the implementation definition `(defun p3/org-export-to-office`.

This verifies ownership moved without changing exporter implementation/reload semantics.

- [ ] **Step 7: Run architecture plus all six focused tests**

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

- [ ] **Step 8: Verify untouched exporter files and inspect the whole `config.org` diff**

```bash
git diff --exit-code master -- lisp/p3-org-export.el test/p3-org-export-test.el
git diff --check master...HEAD
git diff master...HEAD -- config.org
```

Expected: exporter command exits 0 with no output; `config.org` diff is limited to the Org/Agenda, Org-roam, and Presentation regions. If connector whole-file replacement introduced unrelated blank-line or content changes, restore them before proceeding.

- [ ] **Step 9: Commit Task 4**

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
- Consumes: six new Lisp files and six new focused tests.
- Produces: warnings-as-errors compilation, three runtime-load smoke checks, Ubuntu full-suite coverage, and Windows source-level boundary coverage without optional-package installation.

- [ ] **Step 1: Add all six new Lisp files to Ubuntu byte compilation**

Add these exact paths to the existing `batch-byte-compile` list:

```text
lisp/p3-org.el
lisp/p3-config-org.el
lisp/p3-org-roam.el
lisp/p3-config-org-roam.el
lisp/p3-org-present.el
lisp/p3-config-org-present.el
```

Keep the existing package-install suppression:

```elisp
(require 'use-package-ensure)
(setq use-package-ensure-function (lambda (&rest _) t))
```

Do not install Org-roam, org-present, hide-mode-line, or visual-fill-column. Compiler failures caused only by unknown external variables/functions are resolved with declaration-only source forms, not package installation.

- [ ] **Step 2: Add an exact Org-core runtime smoke step**

Add this workflow command:

```bash
emacs -Q --batch \
  -L lisp \
  --eval '(setq user-emacs-directory (file-name-as-directory default-directory))' \
  --eval '(require (quote use-package-ensure))' \
  --eval '(setq use-package-ensure-function (lambda (&rest _) t))' \
  -l lisp/p3-config-loader.el \
  -l lisp/p3-config-org.el \
  --eval '(unless (and (featurep (quote p3-config-org))
                       (featurep (quote p3-org))
                       (eq org-startup-folded (quote content))
                       (eq org-confirm-babel-evaluate t)
                       (featurep (quote p3-org-export)))
             (kill-emacs 1))'
```

This deliberately exercises the unchanged `use-package p3-org-export :demand t` path instead of exact-source loading the exporter.

- [ ] **Step 3: Add an exact stubbed Org-roam runtime smoke step**

Use this command so no database or third-party package is installed:

```bash
emacs -Q --batch \
  -L lisp \
  --eval '(setq user-emacs-directory (file-name-as-directory default-directory))' \
  --eval '(require (quote use-package-ensure))' \
  --eval '(setq use-package-ensure-function (lambda (&rest _) t))' \
  --eval '(defun org-roam-db-autosync-mode (&optional _arg) t)' \
  --eval '(provide (quote org-roam))' \
  -l lisp/p3-config-loader.el \
  -l lisp/p3-config-org-roam.el \
  --eval '(unless (and (featurep (quote p3-config-org-roam))
                       (featurep (quote p3-org-roam))
                       (equal org-roam-directory "~/org/notes/roam/"))
             (kill-emacs 1))'
```

If `use-package` requires a specific Org-roam subfeature solely because of macro expansion on the runner version, provide that feature in this smoke command; do not install or initialize Org-roam. No smoke code may call a real database function.

- [ ] **Step 4: Add an exact stubbed presentation runtime smoke step**

Use:

```bash
emacs -Q --batch \
  -L lisp \
  --eval '(setq user-emacs-directory (file-name-as-directory default-directory))' \
  --eval '(require (quote use-package-ensure))' \
  --eval '(setq use-package-ensure-function (lambda (&rest _) t))' \
  --eval '(require (quote org))' \
  --eval '(defvar org-present-mode-keymap (make-sparse-keymap))' \
  --eval '(provide (quote hide-mode-line))' \
  --eval '(provide (quote visual-fill-column))' \
  --eval '(provide (quote org-present))' \
  -l lisp/p3-config-loader.el \
  -l lisp/p3-config-org-present.el \
  --eval '(unless (and (featurep (quote p3-config-org-present))
                       (featurep (quote p3-org-present))
                       (featurep (quote face-remap))
                       (equal org-present-text-scale 4))
             (kill-emacs 1))'
```

The smoke test must not invoke `p3/org-present-start` or either presentation hook.

- [ ] **Step 5: Load all six new focused tests in the Ubuntu ERT command**

Add:

```text
test/p3-org-test.el
test/p3-config-org-test.el
test/p3-org-roam-test.el
test/p3-config-org-roam-test.el
test/p3-org-present-test.el
test/p3-config-org-present-test.el
```

Keep `-l test/p3-org-export-test.el` unchanged.

- [ ] **Step 6: Extend Windows only for source-level boundary coverage**

Add path triggers for:

```text
lisp/p3-config-org.el
lisp/p3-config-org-roam.el
lisp/p3-config-org-present.el
test/p3-config-org-test.el
test/p3-config-org-roam-test.el
test/p3-config-org-present-test.el
```

Load those three config-boundary tests in the existing Windows config-architecture ERT command. Do not add Org-roam/presentation runtime smoke tests on Windows and do not add behavior-library triggers that would spend Windows Actions minutes without corresponding behavior coverage.

- [ ] **Step 7: Perform pre-PR static rejection checks**

Run or reproduce through connector diffs:

```bash
git diff --check master...HEAD
git diff --exit-code master -- lisp/p3-org-export.el test/p3-org-export-test.el
git diff master...HEAD -- config.org
git diff master...HEAD -- .github/workflows/emacs-tests.yml
git diff master...HEAD -- .github/workflows/windows-platform-tests.yml
```

Reject any unrelated change, package-install command for Org-roam/presentation dependencies, broad display policy, citation/LaTeX/Poly-R/Projectile change, or normalization of the trailing `#`/anonymous timestamp hook.

- [ ] **Step 8: Commit CI wiring**

```bash
git add .github/workflows/emacs-tests.yml .github/workflows/windows-platform-tests.yml
git commit -m "Cover Org configuration boundaries in CI"
```

- [ ] **Step 9: Open the PR only after the implementation branch is coherent enough for one CI cycle**

PR summary must explicitly state:

- structural/behavior-preserving extraction only;
- exporter implementation and reload behavior unchanged;
- trailing tagged-header `#` intentionally preserved;
- `face-remap` now travels with the extracted behavior that calls it, at the same effective point in startup;
- optional package surfaces are stubbed rather than installed in smoke checks;
- Citar/BibTeX/RefTeX, LaTeX, and Poly-R are outside scope.

- [ ] **Step 10: Verify final CI from the exact PR head**

Ubuntu must show success for:

1. warnings-as-errors byte compilation;
2. Org-core runtime smoke;
3. stubbed Org-roam runtime smoke;
4. stubbed presentation runtime smoke;
5. full ERT suite with zero unexpected failures.

Windows must show success for the existing platform/project gate and config architecture gate including the three new source-level boundary suites.

For any failure, inspect the exact failing job/assertion and fix its root cause. Do not create diagnostic workflows or repeatedly push speculative changes.

- [ ] **Step 11: Perform final adversarial review before merge recommendation**

Review the aggregate PR specifically for behavior drift, exporter reload drift, direct dependency mistakes, optional-package installation, `config.org` ordering changes, capture/template/keybinding changes, incomplete presentation restoration testing, or unrelated edits.

Do not merge without explicit user approval.
