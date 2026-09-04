# ESS Configuration Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move declarative ESS/R-mode configuration into `p3-config-ess.el` while preserving all current ESS/R behavior and leaving `p3-ess.el` focused on project/session/process ownership.

**Architecture:** `config.org` will exact-source load one new configuration owner, `p3-config-ess.el`. That module will exact-source load `p3-ess.el` and `p3-r-tools.el`, explicitly invoke `p3/ess-setup`, own ESS package wiring and ESS-specific Company configuration, and leave Windows R executable selection in `config.org` immediately afterward. Existing process/session code and R workflow commands remain behaviorally unchanged.

**Tech Stack:** Emacs Lisp, Emacs 29+, Org Babel config cache, `use-package`, ESS, Company, ERT, GitHub Actions on Ubuntu and Windows.

**Spec:** `docs/superpowers/specs/2026-09-04-ess-config-boundary-design.md`

## Global Constraints

- Preserve the user's current R/ESS workflow; this is an extraction/refactoring PR, not a redesign.
- Do not fix the existing `company-dabbrev` compatibility error in this PR.
- Do not change Company backend composition, ESS process/session semantics, R startup arguments, Lintr/Flycheck policy, ESS font-lock, project identity, R workflow commands, window placement, keybindings, package management, Python, Org, terminal, or Projectile behavior.
- Keep `p3/windows-configure-r-program` in `config.org` immediately after the ESS configuration module load.
- Keep the existing narrow `inferior-ess-r-mode` display rule unchanged in `p3-config-workspace.el`.
- Use the existing exact-source local module loader; add no registry, discovery, or generalized reload mechanism.
- Move `p3/ess-inferior-mode-setup` to the configuration module; `p3-ess.el` must retain process/session ownership only.
- `p3-config-ess.el` must explicitly call `p3/ess-setup` after exact-source loading `p3-ess.el`.
- Preserve the exact ESS Company backend value:

```elisp
'((:separate
   company-R-library company-R-args company-R-objects
   company-dabbrev-code
   :with company-yasnippet)
  company-capf)
```

- Generated `config.el` and `.elc` files remain ignored and untracked.
- Do not use repeated CI pushes as a diagnostic loop; batch compiler/declaration fixes and use one final Ubuntu/Windows gate after local/static verification.

---

## File Map

- Create `lisp/p3-config-ess.el`: declarative ESS/R configuration owner.
- Create `test/p3-config-ess-test.el`: semantic source tests for the new module without loading optional third-party packages.
- Modify `lisp/p3-ess.el`: remove only inferior-buffer configuration helper/declarations; retain project/process behavior.
- Modify `lisp/p3-config-completion.el`: remove only ESS-specific Company backend data and hook function.
- Modify `config.org`: remove the early `p3-r-tools` stanza and large inline ESS block; load `p3-config-ess` instead.
- Modify `test/p3-config-test.el`: update module ownership/order assertions and remove assumptions that ESS is inline.
- Modify `.github/workflows/emacs-tests.yml`: byte-compile `p3-config-ess.el` and run `p3-config-ess-test.el`.
- Modify `.github/workflows/windows-platform-tests.yml`: trigger on the new module/test and run the source-level ESS boundary test on Windows.

---

### Task 1: Add semantic tests and the new ESS configuration module

**Files:**
- Create: `test/p3-config-ess-test.el`
- Create: `lisp/p3-config-ess.el`

**Interfaces:**
- Consumes: `p3/config-load-module` from `p3-config-loader.el`, `p3/ess-setup` from `p3-ess.el`, `p3-r-command-map` and R workflow commands from `p3-r-tools.el`.
- Produces: feature `p3-config-ess`; functions `p3/ess-inferior-mode-setup`, `p3/ess-company-config`, and `compile-rmd`; variable `p3/r-company-backends`.

- [ ] **Step 1: Create source-parsing test helpers and failing semantic tests**

Create `test/p3-config-ess-test.el` with tests that read Lisp forms from the tracked source instead of loading optional ESS/Company packages:

```elisp
;;; p3-config-ess-test.el --- Tests for ESS configuration ownership -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defconst p3-config-ess-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(defun p3-config-ess-test--path (relative)
  (expand-file-name relative p3-config-ess-test--root))

(defun p3-config-ess-test--forms (relative)
  (with-temp-buffer
    (insert-file-contents (p3-config-ess-test--path relative))
    (goto-char (point-min))
    (let (forms)
      (condition-case nil
          (while t
            (push (read (current-buffer)) forms))
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
     (and (consp form)
          (eq (car form) 'defvar)
          (eq (cadr form) symbol)))))

(defun p3-config-ess-test--defun-form (symbol)
  (p3-config-ess-test--find-top-level
   "lisp/p3-config-ess.el"
   (lambda (form)
     (and (consp form)
          (eq (car form) 'defun)
          (eq (cadr form) symbol)))))

(ert-deftest p3-config-ess-loads-behavior-and-r-tools-explicitly ()
  (let ((forms (p3-config-ess-test--forms "lisp/p3-config-ess.el")))
    (should (member '(require 'p3-config-loader) forms))
    (should (member '(p3/config-load-module 'p3-ess) forms))
    (should (member '(p3/ess-setup) forms))
    (should (member '(p3/config-load-module 'p3-r-tools) forms))
    (should (member '(keymap-global-set "C-c R" p3-r-command-map) forms))))

(ert-deftest p3-config-ess-preserves-company-backends-exactly ()
  (let ((form (p3-config-ess-test--defvar-form 'p3/r-company-backends)))
    (should form)
    (should
     (equal
      (nth 2 form)
      '(quote
        ((:separate
          company-R-library company-R-args company-R-objects
          company-dabbrev-code
          :with company-yasnippet)
         company-capf))))))

(ert-deftest p3-config-ess-preserves-company-buffer-hook ()
  (let ((form (p3-config-ess-test--defun-form 'p3/ess-company-config)))
    (should form)
    (should
     (equal (cdddr form)
            '((setq-local company-backends p3/r-company-backends))))))

(ert-deftest p3-config-ess-preserves-inferior-buffer-setup ()
  (let ((form (p3-config-ess-test--defun-form 'p3/ess-inferior-mode-setup)))
    (should form)
    (should
     (equal (cdddr form)
            '((setq-local ansi-color-for-comint-mode 'filter)
              (smartparens-mode 1))))))

(ert-deftest p3-config-ess-preserves-ess-hooks-and-bindings ()
  (let* ((form (p3-config-ess-test--use-package-form))
         (args (cddr form)))
    (should form)
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
  (let ((contents
         (with-temp-buffer
           (insert-file-contents
            (p3-config-ess-test--path "lisp/p3-config-ess.el"))
           (buffer-string))))
    (dolist (setting
             '("ess-ask-for-ess-directory nil"
               "ess-style 'RStudio"
               "ess-eval-visibly t"
               "ess-toggle-underscore nil"
               "ess-use-flymake nil"
               "ess--command-default-timeout 1"
               "inferior-R-args \"--no-save\""
               "ess-gen-proc-buffer-name-function 'ess-gen-proc-buffer-name:project-or-directory"
               "linters_with_defaults(object_name_linter(c('snake_case','camelCase')), commented_code_linter = NULL, line_length_linter(90), single_quotes_linter=NULL)"))
      (should (string-match-p (regexp-quote setting) contents)))
    (dolist (font-lock
             '("ess-R-fl-keyword:modifiers"
               "ess-R-fl-keyword:fun-defs"
               "ess-R-fl-keyword:keywords"
               "ess-R-fl-keyword:assign-ops"
               "ess-R-fl-keyword:constants"
               "ess-fl-keyword:fun-calls"
               "ess-fl-keyword:numbers"
               "ess-fl-keyword:operators"
               "ess-fl-keyword:delimiters"
               "ess-fl-keyword:="
               "ess-R-fl-keyword:F&T"
               "ess-R-fl-keyword:%op%"))
      (should (string-match-p (regexp-quote font-lock) contents)))))

(ert-deftest p3-config-ess-preserves-rmarkdown-compile-hook ()
  (let ((contents
         (with-temp-buffer
           (insert-file-contents
            (p3-config-ess-test--path "lisp/p3-config-ess.el"))
           (buffer-string))))
    (should (string-match-p "(defun compile-rmd ()" contents))
    (should
     (string-match-p
      (regexp-quote "R -e \"rmarkdown::render('") contents))
    (should (string-match-p
             (regexp-quote "(add-hook 'ess-mode-hook 'compile-rmd)") contents))
    (should (string-match-p
             (regexp-quote "(add-hook 'markdown-mode-hook 'compile-rmd)") contents))))

(provide 'p3-config-ess-test)

;;; p3-config-ess-test.el ends here
```

- [ ] **Step 2: Run the new test file and verify it fails because the module is missing**

Run:

```bash
emacs -Q --batch -L lisp -l test/p3-config-ess-test.el -f ert-run-tests-batch-and-exit
```

Expected: FAIL with a file-missing error for `lisp/p3-config-ess.el`.

- [ ] **Step 3: Create `p3-config-ess.el` with the existing ESS configuration moved verbatim**

Create `lisp/p3-config-ess.el` with this structure and existing values:

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

;;; p3-config-ess.el ends here
```

Do not remove the old definitions yet in this task; the new module is not loaded by `config.org` yet, so this commit is behavior-neutral.

- [ ] **Step 4: Run the source-semantic tests**

Run:

```bash
emacs -Q --batch -L lisp -l test/p3-config-ess-test.el -f ert-run-tests-batch-and-exit
```

Expected: all `p3-config-ess-*` tests PASS.

- [ ] **Step 5: Byte-compile the new module once locally if Emacs is available**

Run:

```bash
emacs -Q --batch -L lisp --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile lisp/p3-config-ess.el
rm -f lisp/p3-config-ess.elc
```

Expected: zero compiler warnings/errors. If a warning names an external variable/function already present in the moved configuration, add only the minimal `defvar`/`declare-function` declaration needed to satisfy the compiler; do not alter runtime behavior.

- [ ] **Step 6: Commit**

```bash
git add lisp/p3-config-ess.el test/p3-config-ess-test.el
git commit -m "Add ESS configuration module"
```

---

### Task 2: Remove ESS configuration from the old behavior/completion owners

**Files:**
- Modify: `lisp/p3-ess.el`
- Modify: `lisp/p3-config-completion.el`
- Modify: `test/p3-config-ess-test.el`
- Test: `test/p3-ess-test.el`

**Interfaces:**
- Consumes: `p3-config-ess.el` from Task 1.
- Produces: `p3-ess.el` with process/session-only responsibility; `p3-config-completion.el` with generic completion-only responsibility.

- [ ] **Step 1: Add failing ownership assertions**

Append to `test/p3-config-ess-test.el`:

```elisp
(ert-deftest p3-ess-library-has-no-buffer-configuration-glue ()
  (let ((contents
         (with-temp-buffer
           (insert-file-contents
            (p3-config-ess-test--path "lisp/p3-ess.el"))
           (buffer-string))))
    (dolist (forbidden '("p3/ess-inferior-mode-setup"
                         "ansi-color-for-comint-mode"
                         "smartparens-mode"))
      (should-not (string-match-p (regexp-quote forbidden) contents)))))

(ert-deftest p3-generic-completion-has-no-ess-company-owner ()
  (let ((contents
         (with-temp-buffer
           (insert-file-contents
            (p3-config-ess-test--path "lisp/p3-config-completion.el"))
           (buffer-string))))
    (dolist (forbidden '("p3/r-company-backends"
                         "p3/ess-company-config"
                         "company-R-library"
                         "company-R-args"
                         "company-R-objects"))
      (should-not (string-match-p (regexp-quote forbidden) contents)))))
```

- [ ] **Step 2: Run the two new tests and verify they fail on the old owners**

Run:

```bash
emacs -Q --batch -L lisp -l test/p3-config-ess-test.el \
  --eval "(ert-run-tests-batch-and-exit \"p3-\\(?:ess-library\\|generic-completion\\)\")"
```

Expected: both tests FAIL because the moved definitions still exist in their old files.

- [ ] **Step 3: Remove only inferior-buffer configuration from `p3-ess.el`**

Delete from `lisp/p3-ess.el`:

```elisp
(declare-function smartparens-mode "smartparens" (&optional arg))
(defvar ansi-color-for-comint-mode)

(defun p3/ess-inferior-mode-setup ()
  "Apply personal defaults to an inferior ESS buffer."
  (setq-local ansi-color-for-comint-mode 'filter)
  (smartparens-mode 1))
```

Keep every project/process function, `p3/ess-install-process-advice`, and `p3/ess-setup` unchanged.

- [ ] **Step 4: Remove only ESS-specific Company state from `p3-config-completion.el`**

Delete the top-level compiler declaration if it is no longer used:

```elisp
(defvar company-backends)
```

Within `(use-package company ...)`, remove the current `:init` block containing:

```elisp
(defvar p3/r-company-backends ...)
(defun p3/ess-company-config () ...)
```

Leave the package declaration behavior as:

```elisp
(use-package company
  :hook (after-init . global-company-mode)
  :config
  (setq company-dabbrev-downcase nil))
```

Do not change any Company backend function or replace Company.

- [ ] **Step 5: Run the ownership and existing ESS behavior tests**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-ess-test.el \
  -l test/p3-ess-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: all tests PASS. Existing `p3-ess-*` process/session tests remain unchanged.

- [ ] **Step 6: Commit**

```bash
git add lisp/p3-ess.el lisp/p3-config-completion.el test/p3-config-ess-test.el
git commit -m "Separate ESS behavior from configuration"
```

---

### Task 3: Replace inline ESS configuration with explicit orchestration

**Files:**
- Modify: `config.org`
- Modify: `test/p3-config-test.el`
- Test: `test/p3-config-ess-test.el`
- Test: `test/p3-r-tools-test.el`

**Interfaces:**
- Consumes: feature `p3-config-ess` from Task 1.
- Produces: one authoritative ESS module load in `config.org`; Windows R selection remains immediately afterward.

- [ ] **Step 1: Update configuration tests first**

In `test/p3-config-test.el` make these exact expectation changes:

1. In `p3-config-org-delegates-custom-subsystems-to-modules`, remove `"p3-ess"` from the `use-package` module list and remove `"ess-r-mode"` from the inline package list. Add an assertion for the exact module loader:

```elisp
(should
 (string-match-p
  (regexp-quote "(p3/config-load-module 'p3-config-ess)")
  contents))
```

2. In `p3-config-early-orchestration-order-is-explicit`, add:

```elisp
(ess (p3-config-test--position
      "(p3/config-load-module 'p3-config-ess)" contents))
```

and assert:

```elisp
(should (< completion ess))
(should (< ess r-program))
```

3. In `p3-config-platform-setup-preserves-subsystem-timing`, replace the ESS position needle:

```elisp
(p3-config-test--position "(p3/config-load-module 'p3-config-ess)" contents)
```

4. Rename `p3-config-org-source-loads-five-config-modules` to `p3-config-org-source-loads-six-config-modules` and use:

```elisp
(dolist (module '(p3-config-base p3-config-editing p3-config-completion
                  p3-config-ess p3-config-workspace p3-config-git))
  ...)
```

5. Add to `p3-config-moved-implementation-is-not-inline`:

```elisp
"(use-package p3-r-tools"
"(use-package p3-ess"
"(use-package ess-r-mode"
"(defun compile-rmd"
```

6. Add a focused test that the old executable R-tools owner is gone and Windows ordering remains explicit:

```elisp
(ert-deftest p3-config-ess-orchestration-has-one-owner ()
  (let* ((contents (p3-config-test--contents "config.org"))
         (ess (p3-config-test--position
               "(p3/config-load-module 'p3-config-ess)" contents))
         (r-program (p3-config-test--position
                     "(p3/windows-configure-r-program)" contents)))
    (should-not (string-match-p "(use-package p3-r-tools" contents))
    (should-not (string-match-p
                 (regexp-quote "(keymap-global-set \"C-c R\"") contents))
    (should (= 1
               (let ((start 0) (count 0))
                 (while (string-match
                         (regexp-quote "(p3/config-load-module 'p3-config-ess)")
                         contents start)
                   (setq count (1+ count)
                         start (match-end 0)))
                 count)))
    (should (< ess r-program))))
```

- [ ] **Step 2: Run targeted config tests and verify they fail against the current inline config**

Run:

```bash
emacs -Q --batch -L lisp -l test/p3-config-test.el -f ert-run-tests-batch-and-exit
```

Expected: FAIL on missing `p3-config-ess` orchestration and stale inline ESS/R-tools expectations.

- [ ] **Step 3: Remove the earlier `p3-r-tools` stanza from `config.org`**

Delete the prose and source block under `* Functions` that currently load `p3-r-tools` and bind `C-c R`:

```elisp
(use-package p3-r-tools
  :ensure nil
  :demand t
  :config
  (keymap-global-set "C-c R" p3-r-command-map))
```

Leave `p3-core` and its `C-c e` / `C-c r` bindings untouched.

- [ ] **Step 4: Replace the entire inline ESS block with the new module loader**

Replace the current `use-package p3-ess`, `use-package ess-r-mode`, and later `compile-rmd` block with:

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

Do not move `p3/windows-configure-r-program` into the module.

- [ ] **Step 5: Verify no executable R-tools dependency remains before the ESS module load**

Run:

```bash
git grep -n "p3-r-\|p3-r-command-map\|p3-r-tools" -- config.org
```

Expected: any remaining matches before the ESS section are prose/comments only; no earlier Lisp source block loads `p3-r-tools`, binds `p3-r-command-map`, or invokes a `p3-r-*` function.

- [ ] **Step 6: Run config, ESS boundary, and R workflow tests**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-loader-test.el \
  -l test/p3-config-test.el \
  -l test/p3-config-ess-test.el \
  -l test/p3-ess-test.el \
  -l test/p3-r-tools-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: all loaded tests PASS; R parser test may skip if `Rscript` is unavailable.

- [ ] **Step 7: Commit**

```bash
git add config.org test/p3-config-test.el
git commit -m "Route ESS configuration through its module"
```

---

### Task 4: Wire CI coverage for the new configuration owner

**Files:**
- Modify: `.github/workflows/emacs-tests.yml`
- Modify: `.github/workflows/windows-platform-tests.yml`

**Interfaces:**
- Consumes: `lisp/p3-config-ess.el` and `test/p3-config-ess-test.el`.
- Produces: Ubuntu compiler/full-suite coverage and Windows structural boundary coverage for ESS configuration.

- [ ] **Step 1: Update Ubuntu compile and ERT lists**

In `.github/workflows/emacs-tests.yml`, add `lisp/p3-config-ess.el` after the other config modules and add `test/p3-config-ess-test.el` to the ERT load list:

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

- [ ] **Step 2: Update Windows path triggers and architecture test list**

Add these paths to `.github/workflows/windows-platform-tests.yml`:

```yaml
      - "lisp/p3-config-ess.el"
      - "lisp/p3-ess.el"
      - "lisp/p3-r-tools.el"
      - "test/p3-config-ess-test.el"
      - "test/p3-ess-test.el"
      - "test/p3-r-tools-test.el"
```

Keep Windows byte compilation limited to the existing platform boundary modules; `p3-config-ess.el` contains optional package wiring and is byte-compiled on Ubuntu. Add only the source-level ESS boundary test to the Windows config architecture command:

```yaml
          -l test/p3-config-loader-test.el
          -l test/p3-config-test.el
          -l test/p3-config-ess-test.el
          -l test/p3-commands-test.el
```

This preserves Windows coverage for R-program ordering and source ownership without requiring ESS/Company packages to be installed on the Windows runner.

- [ ] **Step 3: Run a static workflow diff check**

Run:

```bash
git diff --check
git diff -- .github/workflows/emacs-tests.yml .github/workflows/windows-platform-tests.yml
```

Expected: no whitespace errors; only the new module/test coverage is added.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/emacs-tests.yml .github/workflows/windows-platform-tests.yml
git commit -m "Cover ESS configuration boundary in CI"
```

---

### Task 5: Final verification and adversarial review

**Files:**
- Verify all files changed by Tasks 1-4.
- Do not change production behavior unless verification exposes a concrete regression.

**Interfaces:**
- Consumes: completed implementation.
- Produces: merge-ready PR branch with evidence that the extraction preserves behavior.

- [ ] **Step 1: Verify the branch diff is within scope**

Run:

```bash
git diff --check master...HEAD
git diff --stat master...HEAD
git diff master...HEAD -- \
  lisp/p3-config-ess.el \
  lisp/p3-ess.el \
  lisp/p3-config-completion.el \
  config.org \
  test/p3-config-ess-test.el \
  test/p3-config-test.el \
  .github/workflows/emacs-tests.yml \
  .github/workflows/windows-platform-tests.yml
```

Expected: no unrelated Python, Org, terminal, project, window-placement, package-manager, or R workflow implementation changes.

- [ ] **Step 2: Compare moved ESS forms against `master` for semantic equivalence**

Check specifically:

```bash
git show master:config.org | grep -n -A90 -B10 "use-package ess-r-mode"
git show HEAD:lisp/p3-config-ess.el

git show master:lisp/p3-config-completion.el | grep -n -A25 -B5 "p3/r-company-backends"
git show HEAD:lisp/p3-config-ess.el | grep -n -A25 -B5 "p3/r-company-backends"

git show master:lisp/p3-ess.el | grep -n -A8 -B4 "p3/ess-inferior-mode-setup"
git show HEAD:lisp/p3-config-ess.el | grep -n -A8 -B4 "p3/ess-inferior-mode-setup"
```

Expected: moved settings, hooks, keybindings, Company backend contents, `compile-rmd`, and inferior-buffer setup are semantically unchanged.

- [ ] **Step 3: Run the complete local ERT gate if Emacs is available**

Run the same suite as Ubuntu CI, including the new test:

```bash
emacs -Q --batch \
  -L lisp \
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

Expected: zero unexpected failures; platform/R parser tests may retain their existing environment-dependent skips.

- [ ] **Step 4: Confirm generated artifacts remain ignored and untracked**

Run:

```bash
git check-ignore -q config.el
git check-ignore -q lisp/example.elc
test -z "$(git ls-files 'config.el' '*.elc')"
```

Expected: all commands succeed and no generated artifacts are tracked.

- [ ] **Step 5: Open/update the PR and run one final Ubuntu/Windows Actions cycle**

Push the final branch once. Verify both pull-request workflows on the resulting PR merge ref:

- Ubuntu `Emacs tests`: byte compilation succeeds, full ERT has zero unexpected failures.
- Windows `Windows platform tests`: platform/project tests and config architecture tests have zero unexpected failures.

Do not push intermediate diagnostic commits merely to probe CI. If CI fails, pull the exact failing job log, fix the root cause locally/static-first, and rerun once.

- [ ] **Step 6: Perform a final adversarial review before merge**

Reject the PR if any of these are true:

- `p3-ess.el` still contains Smartparens/ANSI buffer configuration;
- `p3-config-completion.el` still owns ESS-specific Company state;
- `p3-config-ess.el` fails to call `p3/ess-setup` explicitly;
- `p3-r-tools.el` public behavior changed;
- any ESS keybinding/settings/backend value differs from `master` without an explicit approved reason;
- Windows R selection moved inside the module or changed ordering;
- the narrow ESS display rule moved or broadened;
- the Company compatibility bug was mixed into this PR;
- generated artifacts are tracked;
- CI reports an unexpected failure.

If none apply, report the branch as merge-ready but do not merge without explicit user approval.
