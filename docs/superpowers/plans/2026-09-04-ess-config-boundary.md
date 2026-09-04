# ESS Configuration Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move declarative ESS/R-mode configuration into `p3-config-ess.el` while preserving the current R/ESS workflow and leaving `p3-ess.el` focused on project/session/process ownership.

**Architecture:** `config.org` exact-source loads one new configuration owner, `p3-config-ess.el`. That module exact-source loads `p3-ess.el` and `p3-r-tools.el`, explicitly invokes `p3/ess-setup`, owns ESS package wiring and ESS-specific Company configuration, and leaves Windows R executable selection in `config.org` immediately afterward. Existing process/session code and R workflow commands remain behaviorally unchanged.

**Tech Stack:** Emacs Lisp, Emacs 29+, Org Babel config cache, `use-package`, ESS, Company, ERT, GitHub Actions on Ubuntu and Windows.

**Spec:** `docs/superpowers/specs/2026-09-04-ess-config-boundary-design.md`

## Global Constraints

- Preserve current ESS/R behavior; this is an extraction/refactoring PR.
- Do not fix the existing `company-dabbrev` compatibility error.
- Do not change Company backend composition, ESS process/session semantics, R startup arguments, Lintr/Flycheck policy, ESS font-lock, project identity, R workflow commands, window placement, keybindings, package management, Python, Org, terminal, or Projectile behavior.
- Keep `p3/windows-configure-r-program` in `config.org` immediately after the ESS module load.
- Keep the narrow `inferior-ess-r-mode` display rule unchanged in `p3-config-workspace.el`.
- Use the existing exact-source module loader; add no registry, discovery, or generalized reload mechanism.
- Move `p3/ess-inferior-mode-setup` into `p3-config-ess.el`; `p3-ess.el` retains process/session ownership only.
- `p3-config-ess.el` must explicitly call `p3/ess-setup` after exact-source loading `p3-ess.el`.
- Preserve this exact Company backend value:

```elisp
'((:separate
   company-R-library company-R-args company-R-objects
   company-dabbrev-code
   :with company-yasnippet)
  company-capf)
```

- Generated `config.el` and `.elc` files remain ignored and untracked.
- Use one final Ubuntu/Windows CI cycle after local/static verification rather than iterative CI diagnostics.

---

## File Map

- Create `lisp/p3-config-ess.el` — declarative ESS/R configuration owner.
- Create `test/p3-config-ess-test.el` — semantic source tests that do not require optional third-party packages at runtime.
- Modify `lisp/p3-ess.el` — remove inferior-buffer configuration only.
- Modify `lisp/p3-config-completion.el` — remove ESS-specific Company ownership only.
- Modify `config.org` — remove the early `p3-r-tools` stanza and inline ESS implementation; load `p3-config-ess` instead.
- Modify `test/p3-config-test.el` — update ownership/order assertions.
- Modify `.github/workflows/emacs-tests.yml` — compile/test the new module.
- Modify `.github/workflows/windows-platform-tests.yml` — trigger on ESS boundary files and run source-level ESS boundary tests.

---

### Task 1: Add semantic tests and the new ESS configuration module

**Files:**
- Create: `test/p3-config-ess-test.el`
- Create: `lisp/p3-config-ess.el`

**Interfaces:**
- Consumes: `p3/config-load-module`, `p3/ess-setup`, `p3-r-command-map`, existing `p3-r-*` commands.
- Produces: feature `p3-config-ess`; functions `p3/ess-inferior-mode-setup`, `p3/ess-company-config`, `compile-rmd`; variable `p3/r-company-backends`.

- [ ] **Step 1: Write failing semantic source tests**

Create `test/p3-config-ess-test.el`:

```elisp
;;; p3-config-ess-test.el --- ESS configuration boundary tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'seq)

(defconst p3-config-ess-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(defun p3-config-ess-test--path (relative)
  (expand-file-name relative p3-config-ess-test--root))

(defun p3-config-ess-test--contents (relative)
  (with-temp-buffer
    (insert-file-contents (p3-config-ess-test--path relative))
    (buffer-string)))

(defun p3-config-ess-test--forms (relative)
  (with-temp-buffer
    (insert-file-contents (p3-config-ess-test--path relative))
    (goto-char (point-min))
    (let (forms)
      (condition-case nil
          (while t (push (read (current-buffer)) forms))
        (end-of-file nil))
      (nreverse forms))))

(defun p3-config-ess-test--find-top-level (relative predicate)
  (seq-find predicate (p3-config-ess-test--forms relative)))

(defun p3-config-ess-test--use-package-form ()
  (p3-config-ess-test--find-top-level
   "lisp/p3-config-ess.el"
   (lambda (form)
     (and (consp form)
          (eq (car form) 'use-package)
          (eq (cadr form) 'ess-r-mode)))))

(defun p3-config-ess-test--defvar-form (symbol)
  (p3-config-ess-test--find-top-level
   "lisp/p3-config-ess.el"
   (lambda (form)
     (and (consp form) (eq (car form) 'defvar) (eq (cadr form) symbol)))))

(defun p3-config-ess-test--defun-form (symbol)
  (p3-config-ess-test--find-top-level
   "lisp/p3-config-ess.el"
   (lambda (form)
     (and (consp form) (eq (car form) 'defun) (eq (cadr form) symbol)))))

(defun p3-config-ess-test--setq-pairs ()
  (let* ((form (p3-config-ess-test--use-package-form))
         (setq-form (plist-get (cddr form) :config)))
    (should (eq (car-safe setq-form) 'setq))
    (seq-partition (cdr setq-form) 2)))

(ert-deftest p3-config-ess-load-order-is-explicit ()
  (let ((forms (p3-config-ess-test--forms "lisp/p3-config-ess.el")))
    (should (member '(require 'p3-config-loader) forms))
    (should (member '(p3/config-load-module 'p3-ess) forms))
    (should (member '(p3/ess-setup) forms))
    (should (member '(p3/config-load-module 'p3-r-tools) forms))
    (should (member '(keymap-global-set "C-c R" p3-r-command-map) forms))))

(ert-deftest p3-config-ess-preserves-company-backends-exactly ()
  (should
   (equal
    (nth 2 (p3-config-ess-test--defvar-form 'p3/r-company-backends))
    '(quote
      ((:separate
        company-R-library company-R-args company-R-objects
        company-dabbrev-code
        :with company-yasnippet)
       company-capf)))))

(ert-deftest p3-config-ess-preserves-company-buffer-hook ()
  (should
   (equal
    (cddddr (p3-config-ess-test--defun-form 'p3/ess-company-config))
    '((setq-local company-backends p3/r-company-backends)))))

(ert-deftest p3-config-ess-preserves-inferior-buffer-setup ()
  (should
   (equal
    (cddddr (p3-config-ess-test--defun-form 'p3/ess-inferior-mode-setup))
    '((setq-local ansi-color-for-comint-mode 'filter)
      (smartparens-mode 1)))))

(ert-deftest p3-config-ess-preserves-hooks-and-bindings ()
  (let* ((form (p3-config-ess-test--use-package-form))
         (args (cddr form)))
    (should
     (equal
      (plist-get args :hook)
      '((inferior-ess-mode . p3/ess-inferior-mode-setup)
        (ess-r-post-run . p3-r-load-view-data-frame)
        (ess-r-mode . p3/ess-company-config)
        (ess-r-mode . p3/use-project-root-as-default-dir)
        (ess-mode . (lambda () (modify-syntax-entry ?_ "w"))))))
    (should
     (equal
      (plist-get args :bind)
      '(:map ess-mode-map
        ("C-<return>" . nil)
        ("S-<return>" . ess-eval-region-or-line-visibly-and-step)
        ("C-." . p3-r-insert-pipe)
        ("C-c i" . p3-r-evaluate-library-section)
        ("C-c v" . p3-r-view-data-frame-at-point)
        ("C-c m" . p3-r-targets-make)
        ("C-c d" . p3-r-targets-make-debug)
        ("C-c l" . p3-r-targets-load-at-point)
        :map inferior-ess-r-mode-map
        ("C-c v" . p3-r-view-data-frame-at-point)
        ("C-c m" . p3-r-targets-make)
        ("C-c d" . p3-r-targets-make-debug)
        ("C-c l" . p3-r-targets-load-at-point))))))

(ert-deftest p3-config-ess-preserves-sensitive-settings ()
  (let ((pairs (p3-config-ess-test--setq-pairs)))
    (dolist (pair
             '((ess-ask-for-ess-directory nil)
               (ess-style 'RStudio)
               (ess-eval-visibly t)
               (ess-toggle-underscore nil)
               (ess-use-flymake nil)
               (ess--command-default-timeout 1)
               (inferior-R-args "--no-save")
               (ess-gen-proc-buffer-name-function
                'ess-gen-proc-buffer-name:project-or-directory)))
      (should (member pair pairs)))
    (should
     (member
      '(flycheck-lintr-linters
        "linters_with_defaults(object_name_linter(c('snake_case','camelCase')), commented_code_linter = NULL, line_length_linter(90), single_quotes_linter=NULL)")
      pairs))
    (should
     (member
      '(ess-R-font-lock-keywords
        '((ess-R-fl-keyword:modifiers . t)
          (ess-R-fl-keyword:fun-defs . t)
          (ess-R-fl-keyword:keywords . t)
          (ess-R-fl-keyword:assign-ops)
          (ess-R-fl-keyword:constants . t)
          (ess-fl-keyword:fun-calls . t)
          (ess-fl-keyword:numbers . t)
          (ess-fl-keyword:operators . t)
          (ess-fl-keyword:delimiters . t)
          (ess-fl-keyword:= . t)
          (ess-R-fl-keyword:F&T . t)
          (ess-R-fl-keyword:%op% . t)))
      pairs))))

(ert-deftest p3-config-ess-preserves-rmarkdown-compile-hook ()
  (let ((contents (p3-config-ess-test--contents "lisp/p3-config-ess.el")))
    (should (string-match-p (regexp-quote "(defun compile-rmd ()") contents))
    (should (string-match-p
             (regexp-quote "R -e \"rmarkdown::render('") contents))
    (should (string-match-p
             (regexp-quote "(add-hook 'ess-mode-hook 'compile-rmd)") contents))
    (should (string-match-p
             (regexp-quote "(add-hook 'markdown-mode-hook 'compile-rmd)") contents))))

(provide 'p3-config-ess-test)
```

- [ ] **Step 2: Verify RED**

```bash
emacs -Q --batch -L lisp -l test/p3-config-ess-test.el -f ert-run-tests-batch-and-exit
```

Expected: failure because `lisp/p3-config-ess.el` does not yet exist.

- [ ] **Step 3: Create `lisp/p3-config-ess.el` with the current ESS configuration values**

```elisp
;;; p3-config-ess.el --- ESS and R-mode configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'p3-config-loader)

(p3/config-load-module 'p3-ess)
(declare-function p3/ess-setup "p3-ess" ())
(p3/ess-setup)

(p3/config-load-module 'p3-r-tools)

(defvar ansi-color-for-comint-mode)
(defvar company-backends)
(defvar ess-ask-for-ess-directory)
(defvar ess-style)
(defvar ess-eval-visibly)
(defvar ess-toggle-underscore)
(defvar ess-use-flymake)
(defvar flycheck-lintr-linters)
(defvar ess--command-default-timeout)
(defvar inferior-R-args)
(defvar ess-R-font-lock-keywords)
(defvar ess-gen-proc-buffer-name-function)
(defvar p3-r-command-map)

(declare-function smartparens-mode "smartparens" (&optional arg))

(keymap-global-set "C-c R" p3-r-command-map)

(defvar p3/r-company-backends
  '((:separate
     company-R-library company-R-args company-R-objects
     company-dabbrev-code
     :with company-yasnippet)
    company-capf)
  "Company completion backends used in ESS R buffers.")

(defun p3/ess-company-config ()
  "Configure Company completion for an ESS R buffer."
  (setq-local company-backends p3/r-company-backends))

(defun p3/ess-inferior-mode-setup ()
  "Apply personal defaults to an inferior ESS buffer."
  (setq-local ansi-color-for-comint-mode 'filter)
  (smartparens-mode 1))

(use-package ess-r-mode
  :ensure ess
  :hook ((inferior-ess-mode . p3/ess-inferior-mode-setup)
         (ess-r-post-run . p3-r-load-view-data-frame)
         (ess-r-mode . p3/ess-company-config)
         (ess-r-mode . p3/use-project-root-as-default-dir)
         (ess-mode . (lambda () (modify-syntax-entry ?_ "w"))))
  :bind (:map ess-mode-map
              ("C-<return>" . nil)
              ("S-<return>" . ess-eval-region-or-line-visibly-and-step)
              ("C-." . p3-r-insert-pipe)
              ("C-c i" . p3-r-evaluate-library-section)
              ("C-c v" . p3-r-view-data-frame-at-point)
              ("C-c m" . p3-r-targets-make)
              ("C-c d" . p3-r-targets-make-debug)
              ("C-c l" . p3-r-targets-load-at-point)
         :map inferior-ess-r-mode-map
              ("C-c v" . p3-r-view-data-frame-at-point)
              ("C-c m" . p3-r-targets-make)
              ("C-c d" . p3-r-targets-make-debug)
              ("C-c l" . p3-r-targets-load-at-point))
  :config
  (setq ess-ask-for-ess-directory nil
        ess-style 'RStudio
        ess-eval-visibly t
        ess-toggle-underscore nil
        ess-use-flymake nil
        flycheck-lintr-linters "linters_with_defaults(object_name_linter(c('snake_case','camelCase')), commented_code_linter = NULL, line_length_linter(90), single_quotes_linter=NULL)"
        ess--command-default-timeout 1
        inferior-R-args "--no-save"
        ess-R-font-lock-keywords
        '((ess-R-fl-keyword:modifiers . t)
          (ess-R-fl-keyword:fun-defs . t)
          (ess-R-fl-keyword:keywords . t)
          (ess-R-fl-keyword:assign-ops)
          (ess-R-fl-keyword:constants . t)
          (ess-fl-keyword:fun-calls . t)
          (ess-fl-keyword:numbers . t)
          (ess-fl-keyword:operators . t)
          (ess-fl-keyword:delimiters . t)
          (ess-fl-keyword:= . t)
          (ess-R-fl-keyword:F&T . t)
          (ess-R-fl-keyword:%op% . t))
        ess-gen-proc-buffer-name-function
        'ess-gen-proc-buffer-name:project-or-directory))

(defun compile-rmd ()
  (set (make-local-variable 'compile-command)
       (concat "R -e \"rmarkdown::render('" buffer-file-name "')\"")))

(add-hook 'ess-mode-hook 'compile-rmd)
(add-hook 'markdown-mode-hook 'compile-rmd)

(provide 'p3-config-ess)
```

The old definitions remain in their current owners until Task 2; this module is not yet loaded by `config.org`.

- [ ] **Step 4: Verify GREEN and compile closure**

```bash
emacs -Q --batch -L lisp -l test/p3-config-ess-test.el -f ert-run-tests-batch-and-exit
emacs -Q --batch -L lisp --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile lisp/p3-config-ess.el
rm -f lisp/p3-config-ess.elc
```

Expected: all new tests pass and byte compilation has zero warnings/errors. Add only compiler declarations required for external ESS/Company symbols; do not change behavior.

- [ ] **Step 5: Commit**

```bash
git add lisp/p3-config-ess.el test/p3-config-ess-test.el
git commit -m "Add ESS configuration module"
```

---

### Task 2: Remove configuration from old owners

**Files:**
- Modify: `lisp/p3-ess.el`
- Modify: `lisp/p3-config-completion.el`
- Modify: `test/p3-config-ess-test.el`

**Interfaces:**
- Consumes: new owner from Task 1.
- Produces: process/session-only `p3-ess.el`; generic-only `p3-config-completion.el`.

- [ ] **Step 1: Add failing ownership tests**

Append:

```elisp
(ert-deftest p3-ess-library-has-no-buffer-configuration-glue ()
  (let ((contents (p3-config-ess-test--contents "lisp/p3-ess.el")))
    (dolist (forbidden '("p3/ess-inferior-mode-setup"
                         "ansi-color-for-comint-mode"
                         "smartparens-mode"))
      (should-not (string-match-p (regexp-quote forbidden) contents)))))

(ert-deftest p3-generic-completion-has-no-ess-company-owner ()
  (let ((contents (p3-config-ess-test--contents
                   "lisp/p3-config-completion.el")))
    (dolist (forbidden '("p3/r-company-backends"
                         "p3/ess-company-config"
                         "company-R-library"
                         "company-R-args"
                         "company-R-objects"))
      (should-not (string-match-p (regexp-quote forbidden) contents)))))
```

- [ ] **Step 2: Verify RED**

```bash
emacs -Q --batch -L lisp -l test/p3-config-ess-test.el -f ert-run-tests-batch-and-exit
```

Expected: the two ownership tests fail on the current old owners.

- [ ] **Step 3: Remove only buffer configuration from `p3-ess.el`**

Delete:

```elisp
(declare-function smartparens-mode "smartparens" (&optional arg))
(defvar ansi-color-for-comint-mode)

(defun p3/ess-inferior-mode-setup ()
  "Apply personal defaults to an inferior ESS buffer."
  (setq-local ansi-color-for-comint-mode 'filter)
  (smartparens-mode 1))
```

Do not alter `p3/ess-project-root`, process registration, lazy R creation, advice installation, or `p3/ess-setup`.

- [ ] **Step 4: Remove only ESS-specific Company ownership from completion**

Remove the now-unused top-level declaration:

```elisp
(defvar company-backends)
```

Replace the Company declaration with:

```elisp
(use-package company
  :hook (after-init . global-company-mode)
  :config
  (setq company-dabbrev-downcase nil))
```

- [ ] **Step 5: Verify GREEN plus existing ESS behavior**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-ess-test.el \
  -l test/p3-ess-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: all tests pass; existing process/session tests are unchanged.

- [ ] **Step 6: Commit**

```bash
git add lisp/p3-ess.el lisp/p3-config-completion.el test/p3-config-ess-test.el
git commit -m "Separate ESS behavior from configuration"
```

---

### Task 3: Replace inline ESS configuration with module orchestration

**Files:**
- Modify: `config.org`
- Modify: `test/p3-config-test.el`

**Interfaces:**
- Consumes: `p3-config-ess` from Task 1.
- Produces: one ESS module load in `config.org`; Windows R selection stays immediately after it.

- [ ] **Step 1: Update tests before changing `config.org`**

In `p3-config-org-delegates-custom-subsystems-to-modules`, use:

```elisp
(dolist (module '("p3-platform" "p3-core" "p3-python" "p3-terminal"
                  "p3-gptel"))
  (should (string-match-p (regexp-quote (format "(use-package %s" module))
                          contents)))
(dolist (package '("python" "eglot" "vterm" "gptel"))
  (should (string-match-p (regexp-quote (format "(use-package %s" package))
                          contents)))
(should
 (string-match-p
  (regexp-quote "(p3/config-load-module 'p3-config-ess)") contents))
```

In `p3-config-early-orchestration-order-is-explicit`, bind:

```elisp
(ess (p3-config-test--position
      "(p3/config-load-module 'p3-config-ess)" contents))
```

and assert:

```elisp
(should (< completion ess))
(should (< ess r-program))
```

In `p3-config-platform-setup-preserves-subsystem-timing`, replace the old ESS needle with:

```elisp
(p3-config-test--position "(p3/config-load-module 'p3-config-ess)" contents)
```

Rename `p3-config-org-source-loads-five-config-modules` to `p3-config-org-source-loads-six-config-modules` and use:

```elisp
(dolist (module '(p3-config-base p3-config-editing p3-config-completion
                  p3-config-ess p3-config-workspace p3-config-git))
  (should
   (string-match-p
    (regexp-quote (format "(p3/config-load-module '%s)" module))
    contents)))
```

Add these forbidden inline forms to `p3-config-moved-implementation-is-not-inline`:

```elisp
"(use-package p3-r-tools"
"(use-package p3-ess"
"(use-package ess-r-mode"
"(defun compile-rmd"
```

Add:

```elisp
(ert-deftest p3-config-ess-orchestration-has-one-owner ()
  (let* ((contents (p3-config-test--contents "config.org"))
         (ess (p3-config-test--position
               "(p3/config-load-module 'p3-config-ess)" contents))
         (r-program (p3-config-test--position
                     "(p3/windows-configure-r-program)" contents)))
    (should-not (string-match-p "(use-package p3-r-tools" contents))
    (should-not
     (string-match-p
      (regexp-quote "(keymap-global-set \"C-c R\"") contents))
    (should (< ess r-program))))
```

- [ ] **Step 2: Verify RED**

```bash
emacs -Q --batch -L lisp -l test/p3-config-test.el -f ert-run-tests-batch-and-exit
```

Expected: failures because ESS is still inline and `p3-config-ess` is not yet loaded by `config.org`.

- [ ] **Step 3: Remove the early R-tools configuration stanza**

Delete from `* Functions`:

```elisp
(use-package p3-r-tools
  :ensure nil
  :demand t
  :config
  (keymap-global-set "C-c R" p3-r-command-map))
```

Leave `p3-core` unchanged.

- [ ] **Step 4: Replace the inline ESS implementation**

Replace the current `use-package p3-ess`, `use-package ess-r-mode`, and `compile-rmd` blocks with:

```org
** ESS

ESS package wiring, R-mode hooks, keybindings, buffer defaults, and ESS-specific
Company configuration live in =lisp/p3-config-ess.el=. Project-aware ESS
process/session behavior remains in =lisp/p3-ess.el=, while project templates
and user-facing R workflow commands remain in =lisp/p3-r-tools.el=.

#+BEGIN_SRC emacs-lisp
  (p3/config-load-module 'p3-config-ess)
#+END_SRC

On Windows, select the R executable here, preserving the existing subsystem
startup boundary.

#+BEGIN_SRC emacs-lisp
  (p3/windows-configure-r-program)
#+END_SRC
```

- [ ] **Step 5: Verify there is no earlier executable R-tools dependency**

```bash
git grep -n "p3-r-\|p3-r-command-map\|p3-r-tools" -- config.org
```

Expected: any match before the ESS section is prose/commentary only; no earlier Lisp source block loads `p3-r-tools`, binds `p3-r-command-map`, or invokes `p3-r-*`.

- [ ] **Step 6: Verify GREEN across the affected suites**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-loader-test.el \
  -l test/p3-config-test.el \
  -l test/p3-config-ess-test.el \
  -l test/p3-ess-test.el \
  -l test/p3-r-tools-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: zero unexpected failures; the R parser test may keep its existing environment-dependent skip.

- [ ] **Step 7: Commit**

```bash
git add config.org test/p3-config-test.el
git commit -m "Route ESS configuration through its module"
```

---

### Task 4: Wire CI coverage

**Files:**
- Modify: `.github/workflows/emacs-tests.yml`
- Modify: `.github/workflows/windows-platform-tests.yml`

**Interfaces:**
- Consumes: new module/test.
- Produces: Ubuntu compiler/full-suite coverage and Windows source-boundary coverage.

- [ ] **Step 1: Add Ubuntu compile/test entries**

Add:

```yaml
            lisp/p3-config-completion.el \
            lisp/p3-config-ess.el \
            lisp/p3-config-workspace.el \
```

and:

```yaml
            -l test/p3-config-test.el \
            -l test/p3-config-ess-test.el \
            -l test/p3-project-test.el \
```

- [ ] **Step 2: Extend Windows path triggers and source tests**

Add triggers:

```yaml
      - "lisp/p3-config-ess.el"
      - "lisp/p3-ess.el"
      - "lisp/p3-r-tools.el"
      - "test/p3-config-ess-test.el"
      - "test/p3-ess-test.el"
      - "test/p3-r-tools-test.el"
```

Keep Windows byte compilation limited to the existing boundary modules. Add only the source-level ESS boundary test to the Windows architecture command:

```yaml
          -l test/p3-config-loader-test.el
          -l test/p3-config-test.el
          -l test/p3-config-ess-test.el
          -l test/p3-commands-test.el
          -l test/p3-git-test.el
```

- [ ] **Step 3: Static-check the workflow diff**

```bash
git diff --check
git diff -- .github/workflows/emacs-tests.yml .github/workflows/windows-platform-tests.yml
```

Expected: no whitespace errors and no unrelated workflow changes.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/emacs-tests.yml .github/workflows/windows-platform-tests.yml
git commit -m "Cover ESS configuration boundary in CI"
```

---

### Task 5: Final verification and adversarial review

**Files:**
- Verify all changed files; do not expand scope.

**Interfaces:**
- Consumes: Tasks 1-4.
- Produces: merge-ready branch; merge still requires explicit user approval.

- [ ] **Step 1: Check scope and whitespace**

```bash
git diff --check master...HEAD
git diff --stat master...HEAD
```

Expected changed implementation/test files only:

```text
config.org
lisp/p3-config-ess.el
lisp/p3-ess.el
lisp/p3-config-completion.el
test/p3-config-ess-test.el
test/p3-config-test.el
.github/workflows/emacs-tests.yml
.github/workflows/windows-platform-tests.yml
```

plus the approved spec/plan documents.

- [ ] **Step 2: Compare moved forms with `master`**

```bash
git show master:config.org | grep -n -A90 -B10 "use-package ess-r-mode"
git show HEAD:lisp/p3-config-ess.el

git show master:lisp/p3-config-completion.el | grep -n -A25 -B5 "p3/r-company-backends"
git show HEAD:lisp/p3-config-ess.el | grep -n -A25 -B5 "p3/r-company-backends"

git show master:lisp/p3-ess.el | grep -n -A8 -B4 "p3/ess-inferior-mode-setup"
git show HEAD:lisp/p3-config-ess.el | grep -n -A8 -B4 "p3/ess-inferior-mode-setup"
```

Expected: settings, hooks, bindings, Company backend contents, `compile-rmd`, and inferior-buffer setup are semantically unchanged.

- [ ] **Step 3: Run the complete local ERT gate if Emacs is available**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-loader-test.el \
  -l test/p3-config-test.el \
  -l test/p3-config-ess-test.el \
  -l test/p3-project-test.el \
  -l test/p3-core-test.el \
  -l test/p3-platform-test.el \
  -l test/p3-python-test.el \
  -l test/p3-terminal-test.el \
  -l test/p3-ess-test.el \
  -l test/p3-gptel-test.el \
  -l test/p3-r-tools-test.el \
  -l test/p3-org-export-test.el \
  -l test/p3-commands-test.el \
  -l test/p3-git-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: zero unexpected failures; existing environment-dependent skips may remain.

- [ ] **Step 4: Confirm generated artifacts remain ignored/untracked**

```bash
git check-ignore -q config.el
git check-ignore -q lisp/example.elc
test -z "$(git ls-files 'config.el' '*.elc')"
```

- [ ] **Step 5: Push once and verify the final PR merge-ref CI**

Required final gates:

```text
Ubuntu: Emacs tests — byte compilation succeeds; full ERT has zero unexpected failures.
Windows: Windows platform tests — platform/project and config architecture tests have zero unexpected failures.
```

If CI fails, retrieve the exact job log and fix the root cause without adding diagnostic machinery or repeated probe pushes.

- [ ] **Step 6: Final rejection-oriented review**

Reject if any of the following is true:

```text
p3-ess.el still owns Smartparens/ANSI buffer configuration.
p3-config-completion.el still owns ESS-specific Company state.
p3-config-ess.el does not explicitly call p3/ess-setup.
p3-r-tools.el public behavior changed.
Any ESS binding/setting/backend value differs from master without approval.
Windows R selection moved or changed order.
The narrow ESS display rule moved or broadened.
The Company compatibility bug was mixed into this PR.
Generated artifacts are tracked.
CI has an unexpected failure.
```

If none apply, report merge-ready; do not merge without explicit user approval.
