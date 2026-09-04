# Configuration Module Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the personal Emacs configuration so `config.org` becomes a concise orchestration map, five tracked `p3-config-*` modules own declarative configuration, and reusable generic/Git behavior lives in `p3-commands.el` and `p3-git.el`, without changing user-facing behavior.

**Architecture:** Keep the PR #11 single generated `config.el` cache. Add one exact-source local-module loader to `p3-config-loader.el`; `config.org` explicitly uses it for the five new configuration modules, while `p3-config-base.el` and `p3-config-git.el` exact-source-load the two newly extracted behavior libraries so `C-c r` still picks up edits. Preserve the early startup order `load-prefer-newer` / auto-compile -> secrets -> Windows Rtools/MSYS2 activation -> ordinary configuration modules, and leave ESS, Python, Org, terminal, GPTel, R-program selection, and shell configuration for later dedicated work.

**Tech Stack:** Emacs Lisp on Emacs 29+, Org/Babel tangling, built-in `use-package`, ERT, GitHub Actions on Ubuntu and Windows.

**Spec:** `docs/superpowers/specs/2026-09-04-config-module-architecture-design.md`

## Global Constraints

- Preserve current one- and two-window workflows.
- Do not broaden `display-buffer-alist`; keep only the existing `inferior-ess-r-mode` rule moved by this PR.
- Do not replace Company, Projectile, the package manager, or the PR #11 config-cache design.
- Keep `config.org` as the top-level human-readable map, but tracked `p3-config-*` and `p3-*` files become authoritative for migrated domains.
- Keep generated `config.el` ignored and fingerprint-validated; do not introduce multi-target tangling.
- Keep `load-prefer-newer`, auto-compile activation, secrets loading, and the existing `p3/windows-configure-rtools` stage in early `config.org` orchestration, in that order.
- Keep `p3/windows-configure-r-program` with ESS/R and `p3/windows-configure-shell` with the existing shell/terminal area.
- Preserve existing command names and keybindings; do not opportunistically rename legacy unprefixed commands in this PR.
- The `p3-commands.el` and `p3-git.el` move sets are closed to the exact functions named in the spec.
- Configuration modules may use `use-package`, settings, hooks, bindings, small package glue, and small command maps. Substantial reusable behavior belongs in `p3-*` libraries.
- Do not open the implementation PR until the branch is ready for a full gate; this avoids burning GitHub Actions minutes on every intermediate commit.
- Do not merge without explicit user approval.

## File Structure

### New files

- `lisp/p3-config-base.el` — broad global configuration: dashboard, which-key wiring, package-update UI, fonts/cursor, process/session defaults, backups/autosaves, global modes, line numbers, trash, async/Dired, basic global UI bindings. Exact-source-loads `p3-commands.el`.
- `lisp/p3-config-completion.el` — savehist, Vertico, Orderless, Marginalia, Consult, Embark, Company, and the existing completion-specific helper functions.
- `lisp/p3-config-editing.el` — CUA/delete-selection/whitespace/indentation, smartparens, generic editing bindings, google-this, wgrep, undo-tree, super-save, and multiple-cursors.
- `lisp/p3-config-git.el` — Magit command map/declaration, git-gutter wiring, and binding for the config-and-notes sync command. Exact-source-loads `p3-git.el`.
- `lisp/p3-config-workspace.el` — window/buffer/navigation configuration: transpose-frame, narrow ESS display rule, ace-window, winner, restart-emacs, Avy, window resize bindings, and buffer/window command bindings.
- `lisp/p3-commands.el` — the exact generic command/data move set from the spec.
- `lisp/p3-git.el` — the exact Git/process helper move set from the spec.
- `test/p3-commands-test.el` — focused deterministic tests for extracted generic commands.
- `test/p3-git-test.el` — focused deterministic tests for extracted Git/process helpers.

### Modified files

- `lisp/p3-config-loader.el` — add exact-source local-module loading.
- `config.org` — retain early orchestration; replace migrated implementation blocks with concise module headings and exact-source loader stanzas.
- `test/p3-config-loader-test.el` — exact-source loader tests and stale-bytecode contract support.
- `test/p3-core-test.el` — integration test proving `p3/config-reload` re-evaluates a migrated module source.
- `test/p3-config-test.el` — structural ownership/order tests for the new architecture.
- `.github/workflows/emacs-tests.yml` — byte-compile all new modules and load new ERT files.
- `.github/workflows/windows-platform-tests.yml` — include architecture-sensitive paths, byte-compile portable new boundary files, and run config structural/loader tests on Windows.

---

### Task 1: Add exact-source local module loading and prove reload semantics

**Files:**
- Modify: `lisp/p3-config-loader.el`
- Modify: `test/p3-config-loader-test.el`
- Modify: `test/p3-core-test.el`

**Interfaces:**
- Consumes: existing `user-emacs-directory`, `p3/config-build`, and `p3/config-load-generated`.
- Produces: `p3/config-lisp-directory` and `(p3/config-load-module MODULE)`, where `MODULE` is a symbol and the function loads exactly `lisp/<MODULE>.el` with `load-file` every time it is called.

- [ ] **Step 1: Add failing loader tests for exact source re-evaluation**

Append tests equivalent to the following to `test/p3-config-loader-test.el`:

```elisp
(ert-deftest p3-config-loader-load-module-reloads-exact-source ()
  (let* ((directory (make-temp-file "p3-config-module-test-" t))
         (p3/config-lisp-directory directory)
         (source (expand-file-name "p3-test-module.el" directory)))
    (unwind-protect
        (progn
          (with-temp-file source
            (insert "(setq p3-config-loader-test--module-value 'one)\n"
                    "(provide 'p3-test-module)\n"))
          (setq p3-config-loader-test--module-value nil)
          (provide 'p3-test-module)
          (p3/config-load-module 'p3-test-module)
          (should (eq p3-config-loader-test--module-value 'one))
          (with-temp-file source
            (insert "(setq p3-config-loader-test--module-value 'two)\n"
                    "(provide 'p3-test-module)\n"))
          (p3/config-load-module 'p3-test-module)
          (should (eq p3-config-loader-test--module-value 'two)))
      (setq features (delq 'p3-test-module features))
      (delete-directory directory t))))

(ert-deftest p3-config-loader-load-module-rejects-missing-source ()
  (let ((p3/config-lisp-directory
         (make-temp-file "p3-config-module-test-" t)))
    (unwind-protect
        (should-error (p3/config-load-module 'p3-missing-module)
                      :type 'file-missing)
      (delete-directory p3/config-lisp-directory t))))
```

- [ ] **Step 2: Run only the loader tests and verify RED**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-loader-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: FAIL because `p3/config-lisp-directory` / `p3/config-load-module` do not exist.

- [ ] **Step 3: Implement the exact-source loader**

Add near the existing config path constants in `lisp/p3-config-loader.el`:

```elisp
(defconst p3/config-lisp-directory
  (expand-file-name "lisp" user-emacs-directory)
  "Directory containing tracked local Emacs Lisp modules.")

(defun p3/config--module-path (module)
  "Return the tracked source path for local MODULE."
  (unless (symbolp module)
    (signal 'wrong-type-argument (list 'symbolp module)))
  (let ((name (symbol-name module)))
    (unless (string-match-p "\\`[[:alnum:]-]+\\'" name)
      (user-error "Invalid local module name: %S" module))
    (expand-file-name (concat name ".el") p3/config-lisp-directory)))

(defun p3/config-load-module (module)
  "Load exactly the tracked `.el' source for local MODULE."
  (let ((path (p3/config--module-path module)))
    (unless (file-readable-p path)
      (signal 'file-missing (list "Local module source is missing" path)))
    (load-file path)))
```

Do not use `require`, `load`, module discovery, or `.elc` selection in this helper.

- [ ] **Step 4: Re-run loader tests and verify GREEN**

Run the Step 2 command.

Expected: PASS.

- [ ] **Step 5: Add a failing `p3/config-reload` integration test**

Append to `test/p3-core-test.el` a temporary real Org config plus local module test:

```elisp
(ert-deftest p3-core-config-reload-reloads-current-module-source ()
  (let* ((directory (make-temp-file "p3-core-reload-test-" t))
         (p3/config-source (expand-file-name "config.org" directory))
         (p3/config-generated (expand-file-name "config.el" directory))
         (p3/config-lisp-directory (expand-file-name "lisp" directory))
         (module (expand-file-name "p3-reload-test-module.el"
                                   p3/config-lisp-directory)))
    (unwind-protect
        (progn
          (make-directory p3/config-lisp-directory t)
          (with-temp-file p3/config-source
            (insert "#+begin_src emacs-lisp\n"
                    "(p3/config-load-module 'p3-reload-test-module)\n"
                    "#+end_src\n"))
          (with-temp-file module
            (insert "(setq p3-core-test--reload-value 'one)\n"
                    "(provide 'p3-reload-test-module)\n"))
          (setq p3-core-test--reload-value nil)
          (p3/config-reload)
          (should (eq p3-core-test--reload-value 'one))
          (with-temp-file module
            (insert "(setq p3-core-test--reload-value 'two)\n"
                    "(provide 'p3-reload-test-module)\n"))
          (p3/config-reload)
          (should (eq p3-core-test--reload-value 'two)))
      (setq features (delq 'p3-reload-test-module features))
      (delete-directory directory t))))
```

- [ ] **Step 6: Run core tests and verify GREEN**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-core-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS; no production change to `p3/config-reload` is needed because the generated config will call the new exact-source loader.

- [ ] **Step 7: Byte-compile the loader**

Run:

```bash
emacs -Q --batch -L lisp \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile lisp/p3-config-loader.el
```

Expected: success with no warnings.

- [ ] **Step 8: Commit**

```bash
git add lisp/p3-config-loader.el test/p3-config-loader-test.el test/p3-core-test.el
git commit -m "Add exact-source config module loading"
```

---

### Task 2: Lock down early orchestration ordering before extracting domains

**Files:**
- Modify: `config.org` (`* Startup` early auto-compile/secrets/platform blocks)
- Modify: `test/p3-config-test.el`

**Interfaces:**
- Consumes: `p3/config-load-module` from Task 1 and existing `p3/windows-configure-rtools`.
- Produces: explicit order `load-prefer-newer` -> auto-compile -> secrets -> Rtools/MSYS2. R-program and shell configuration remain later.

- [ ] **Step 1: Write failing structural order tests**

Add a test to `test/p3-config-test.el` that reads `config.org`, records string positions, and asserts:

```elisp
(ert-deftest p3-config-early-orchestration-order-is-explicit ()
  (with-temp-buffer
    (insert-file-contents (expand-file-name "config.org" p3-config-test--root))
    (goto-char (point-min))
    (let ((newer (progn (should (search-forward "(setq load-prefer-newer t)" nil t))
                        (point)))
          auto secrets rtools r-program shell)
      (setq auto
            (progn
              (should (search-forward "(auto-compile-on-load-mode)" nil t))
              (point)))
      (setq secrets
            (progn
              (should (search-forward "(load-file p3/secrets-file)" nil t))
              (point)))
      (setq rtools
            (progn
              (should (search-forward "(p3/windows-configure-rtools)" nil t))
              (point)))
      (setq r-program
            (progn
              (should (search-forward "(p3/windows-configure-r-program)" nil t))
              (point)))
      (setq shell
            (progn
              (should (search-forward "(p3/windows-configure-shell)" nil t))
              (point)))
      (should (< newer auto))
      (should (< auto secrets))
      (should (< secrets rtools))
      (should (< rtools r-program))
      (should (< r-program shell)))))
```

Keep the existing `p3-config-platform-setup-preserves-subsystem-timing` test; update only if the new structure makes its string anchors stale.

- [ ] **Step 2: Run the structural test and verify RED**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-test.el \
  --eval '(ert-run-tests-batch-and-exit "p3-config-early-orchestration-order-is-explicit")'
```

Expected: FAIL because the current block enables auto-compile before setting `load-prefer-newer`.

- [ ] **Step 3: Reorder only the early bootstrap forms**

Change the startup block to this shape:

```elisp
(setq load-prefer-newer t)

(use-package auto-compile
  :demand t
  :config
  (auto-compile-on-load-mode)
  (auto-compile-on-save-mode))

(defconst p3/secrets-file
  (expand-file-name "secrets.el" user-emacs-directory)
  "Private configuration file loaded outside version control.")
(when (file-exists-p p3/secrets-file)
  (load-file p3/secrets-file))

(eval-and-compile
  (add-to-list 'load-path (expand-file-name "lisp" user-emacs-directory)))

(use-package p3-platform
  :ensure nil
  :demand t
  :config
  (p3/windows-configure-rtools))
```

Do not move `p3/windows-configure-r-program` or `p3/windows-configure-shell`.

- [ ] **Step 4: Run the structural test and the real config-build smoke test**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add config.org test/p3-config-test.el
git commit -m "Make config bootstrap ordering explicit"
```

---

### Task 3: Extract the closed generic command library

**Files:**
- Create: `lisp/p3-commands.el`
- Create: `test/p3-commands-test.el`
- Modify later tasks only: `config.org` still contains the original definitions until Task 4 removes them.

**Interfaces:**
- Produces the exact functions/data named in the approved spec: `p3/keybinding-sections`, `p3/keybinding-atlas`, `p3/save-kill-other-buffers`, `p3/sudo-edit`, `p3/region-suffix`, `p3/newline-after-comma-or-space`, `p3/force-quotes`, `p3/byte-compile-init-dir`, `p3/windows-shell`, `move-line`, `move-line-up`, `move-line-down`, `p3/open-in-external-app`, `check-curl-version`, `p3/get-local-buffer-mode`, and `p3/is-current-buffer-mode-inferior-ess-r-mode`.

- [ ] **Step 1: Write focused failing command tests**

Create `test/p3-commands-test.el` with the standard repository root/load-path boilerplate and tests such as:

```elisp
(require 'ert)

(defconst p3-commands-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))
(add-to-list 'load-path (expand-file-name "lisp" p3-commands-test--root))

(require 'p3-commands)

(ert-deftest p3-commands-core-helpers-remain-commands ()
  (dolist (command '(p3/keybinding-atlas
                     p3/save-kill-other-buffers
                     p3/sudo-edit
                     p3/region-suffix
                     p3/newline-after-comma-or-space
                     p3/force-quotes
                     p3/byte-compile-init-dir
                     move-line
                     move-line-up
                     move-line-down
                     p3/open-in-external-app
                     check-curl-version
                     p3/get-local-buffer-mode
                     p3/is-current-buffer-mode-inferior-ess-r-mode))
    (should (commandp command))))

(ert-deftest p3-commands-move-line-down-preserves-column ()
  (with-temp-buffer
    (insert "aa\nbb\ncc\n")
    (goto-char (point-min))
    (forward-char 1)
    (move-line-down 1)
    (should (equal (buffer-string) "bb\naa\ncc\n"))
    (should (= (current-column) 1))))

(ert-deftest p3-commands-keybinding-atlas-keeps-global-section ()
  (should (equal (caar p3/keybinding-sections) "Global")))
```

On non-Windows, do not require `p3/windows-shell` to be defined if its original platform guard is preserved. On Windows, add a conditional command assertion.

- [ ] **Step 2: Run tests and verify RED**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-commands-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: FAIL because `p3-commands.el` does not exist.

- [ ] **Step 3: Create `p3-commands.el` by moving the exact approved definitions verbatim**

Use this file shell:

```elisp
;;; p3-commands.el --- Generic personal interactive commands -*- lexical-binding: t; -*-

(require 'subr-x)
(declare-function dired-get-marked-files "dired" (&optional localp arg filter distinguish-one-marked error))
(declare-function w32-shell-execute "w32fns" (operation document &optional parameters show-flag))

;; Copy the exact current definitions/data listed in this task from config.org.
;; Do not rename, simplify regexes, alter prompts, or change behavior.

(provide 'p3-commands)

;;; p3-commands.el ends here
```

For `p3/windows-shell`, preserve the current Windows-only definition guard. For `p3/open-in-external-app`, preserve all three Windows/macOS/Linux branches exactly.

- [ ] **Step 4: Run command tests and byte compilation**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-commands-test.el \
  -f ert-run-tests-batch-and-exit

emacs -Q --batch -L lisp \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile lisp/p3-commands.el
```

Expected: both succeed with no warnings.

- [ ] **Step 5: Commit**

```bash
git add lisp/p3-commands.el test/p3-commands-test.el
git commit -m "Extract generic personal commands"
```

---

### Task 4: Create the base configuration module and remove migrated base implementation from `config.org`

**Files:**
- Create: `lisp/p3-config-base.el`
- Modify: `config.org` (`* Startup`, `* General`, `* Global settings`, and generic command blocks in `* Functions`)
- Modify: `test/p3-config-test.el`

**Interfaces:**
- Consumes: `(p3/config-load-module 'p3-commands)` from Task 1/3.
- Produces: feature `p3-config-base`; keeps keybinding atlas and newly extracted commands reloadable.

- [ ] **Step 1: Add failing structural ownership tests**

Add assertions to `test/p3-config-test.el` that:

```elisp
(goto-char (point-min))
(should (search-forward "(p3/config-load-module 'p3-config-base)" nil t))
(goto-char (point-min))
(should-not (search-forward "(defconst p3/keybinding-sections" nil t))
(goto-char (point-min))
(should-not (search-forward "(defun p3/keybinding-atlas" nil t))
(goto-char (point-min))
(should-not (search-forward "(defun p3/save-kill-other-buffers" nil t))
```

Also read `lisp/p3-config-base.el` and assert it contains:

```elisp
(p3/config-load-module 'p3-commands)
```

- [ ] **Step 2: Run the new structural test and verify RED**

Run the focused `p3-config-test` selector for the new base ownership test.

Expected: FAIL because the module does not exist and definitions remain inline.

- [ ] **Step 3: Create `p3-config-base.el`**

Start with:

```elisp
;;; p3-config-base.el --- Broad global configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'p3-config-loader)
(p3/config-load-module 'p3-commands)
```

Move the existing blocks, preserving forms and values, for:

- fullscreen default frame;
- dashboard;
- which-key declaration/replacements and `C-c ?` atlas binding;
- package declaration and `p3/package-update`;
- fonts and cursor;
- y/n prompt advice and process-kill prompt glue;
- Comint scroll defaults and scrolling settings;
- delete-by-trash;
- async Dired/package processing;
- global font lock and auto-revert;
- line-number helper and activation;
- backup/autosave directories and version settings;
- Dired;
- all-the-icons / all-the-icons-dired;
- basic font-scale bindings;
- the Windows `C-x C-i` binding for `p3/windows-shell`.

Do **not** move `load-prefer-newer`, auto-compile activation, secrets, or platform activation into this module.

End with:

```elisp
(provide 'p3-config-base)

;;; p3-config-base.el ends here
```

- [ ] **Step 4: Replace migrated blocks in `config.org` with a concise Base section**

After the early orchestration block, add a short explanation plus:

```elisp
(p3/config-load-module 'p3-config-base)
```

Delete the moved implementations from their former sections. For generic commands whose bindings are owned by later tasks, temporarily leave only the binding forms in `config.org` after deleting their function definitions. Do not duplicate function bodies.

Keep the existing `p3-core` loader/bindings in `config.org` for this PR; it is not part of the five-domain extraction.

- [ ] **Step 5: Run structural/config build tests and byte-compile base**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-loader-test.el \
  -l test/p3-config-test.el \
  -l test/p3-core-test.el \
  -l test/p3-commands-test.el \
  -f ert-run-tests-batch-and-exit

emacs -Q --batch -L lisp \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile lisp/p3-config-base.el
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lisp/p3-config-base.el config.org test/p3-config-test.el
git commit -m "Extract broad base configuration"
```

---

### Task 5: Extract completion configuration

**Files:**
- Create: `lisp/p3-config-completion.el`
- Modify: `config.org` (`** Completion-related`)
- Modify: `test/p3-config-test.el`

**Interfaces:**
- Produces: feature `p3-config-completion`, `p3/r-company-backends`, `p3/ess-company-config`, `p3/consult-r-doc-chapter-search`, and `p3/consult-line-all`.

- [ ] **Step 1: Add failing structural tests for completion ownership**

Assert `config.org` contains:

```elisp
(p3/config-load-module 'p3-config-completion)
```

and no longer contains:

```text
(defun p3/consult-r-doc-chapter-search
(defun p3/consult-line-all
(defun p3/ess-company-config
(defvar p3/r-company-backends
(use-package vertico
(use-package company
```

- [ ] **Step 2: Run focused structural test and verify RED**

Expected: FAIL on current inline completion section.

- [ ] **Step 3: Create `p3-config-completion.el`**

Use:

```elisp
;;; p3-config-completion.el --- Completion and search configuration -*- lexical-binding: t; -*-

(require 'use-package)

(declare-function consult-line "consult" (&optional initial start))
(declare-function consult-line-multi "consult" (query &optional initial))
(declare-function consult-ripgrep "consult" (&optional directory initial))
```

Move the current blocks verbatim for:

- savehist;
- Vertico;
- Orderless;
- Marginalia;
- the three Consult declarations;
- `p3/consult-r-doc-chapter-search`;
- `p3/consult-line-all`;
- Consult;
- Embark;
- embark-consult;
- Company, including `p3/r-company-backends`, `p3/ess-company-config`, and `company-dabbrev-downcase`.

Do not move synosaurus or yasnippet in this PR.

End with `(provide 'p3-config-completion)`.

- [ ] **Step 4: Replace the inline completion block with the module stanza**

At the existing completion section position, retain concise prose and:

```elisp
(p3/config-load-module 'p3-config-completion)
```

This keeps completion loading before ESS, preserving availability of `p3/ess-company-config` for the later ESS hook.

- [ ] **Step 5: Run tests and byte compilation**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-test.el \
  -f ert-run-tests-batch-and-exit

emacs -Q --batch -L lisp \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile lisp/p3-config-completion.el
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lisp/p3-config-completion.el config.org test/p3-config-test.el
git commit -m "Extract completion configuration"
```

---

### Task 6: Extract editing configuration while preserving final search bindings

**Files:**
- Create: `lisp/p3-config-editing.el`
- Modify: `config.org` (`* General`, `* Global settings`, `** Editing-related`, `** Multiple cursors`, temporary generic command bindings)
- Modify: `test/p3-config-test.el`

**Interfaces:**
- Consumes: feature `p3-commands`; `p3-config-base` exact-source-loads it before this module.
- Produces: feature `p3-config-editing`.

- [ ] **Step 1: Add failing structural order/ownership tests**

Assert both stanzas exist and editing loads before completion:

```elisp
(let ((editing (progn
                 (goto-char (point-min))
                 (should (search-forward
                          "(p3/config-load-module 'p3-config-editing)" nil t))
                 (point)))
      (completion (progn
                    (goto-char (point-min))
                    (should (search-forward
                             "(p3/config-load-module 'p3-config-completion)" nil t))
                    (point))))
  (should (< editing completion)))
```

Also assert inline `use-package undo-tree`, `use-package super-save`, and `use-package multiple-cursors` are gone.

- [ ] **Step 2: Verify RED**

Run the focused structural test. Expected: FAIL because no editing module exists.

- [ ] **Step 3: Create `p3-config-editing.el`**

Use:

```elisp
;;; p3-config-editing.el --- Generic editing configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'p3-commands)
```

Move the existing forms, preserving their values/bindings, for:

- delete-selection mode;
- before-save whitespace cleanup;
- CUA mode and `cua-auto-tabify-rectangles`;
- `indent-tabs-mode` default;
- default Cyrillic transliteration input method;
- smartparens;
- global compile binding and disabled suspend binding;
- the current initial regex-aware isearch bindings;
- `C-c a` align-region lambda;
- generic extracted-command bindings: `C-c s` -> `p3/region-suffix`, `C-c C-SPC` -> `p3/newline-after-comma-or-space`, `C-c q` -> `p3/force-quotes`, `M-<up>` / `M-<down>` -> move-line commands;
- google-this;
- wgrep;
- undo-tree;
- super-save;
- multiple-cursors.

Load this module at the early general/global editing position, before the completion section. That preserves the current final `C-s` / `C-r` outcome because Consult still loads afterward and rebinds them.

End with `(provide 'p3-config-editing)`.

- [ ] **Step 4: Replace corresponding inline blocks in `config.org`**

Add concise prose plus:

```elisp
(p3/config-load-module 'p3-config-editing)
```

Remove the migrated inline blocks and the temporary generic command binding forms left by Task 4.

- [ ] **Step 5: Run config/command tests and compile**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-test.el \
  -l test/p3-commands-test.el \
  -f ert-run-tests-batch-and-exit

emacs -Q --batch -L lisp \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile lisp/p3-config-editing.el
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lisp/p3-config-editing.el config.org test/p3-config-test.el
git commit -m "Extract editing configuration"
```

---

### Task 7: Extract Git behavior and Git configuration

**Files:**
- Create: `lisp/p3-git.el`
- Create: `lisp/p3-config-git.el`
- Create: `test/p3-git-test.el`
- Modify: `config.org` (`** Git`)
- Modify: `test/p3-config-test.el`

**Interfaces:**
- Produces behavior functions `p3/check-git-installed`, `p3/get-commit-message`, `p3/git-call`, `p3/git-run`, `p3/git-commit-and-push-repository`, `p3/git-commit-and-push-emacs-config`, and `close-magit-buffers`.
- Produces config feature `p3-config-git` and `p3/magit-command-map`.

- [ ] **Step 1: Write failing Git behavior tests**

Create `test/p3-git-test.el` with repository boilerplate and tests such as:

```elisp
(require 'ert)
(require 'cl-lib)
(add-to-list 'load-path
             (expand-file-name "lisp"
                               (file-name-directory
                                (directory-file-name
                                 (file-name-directory
                                  (or load-file-name buffer-file-name))))))
(require 'p3-git)

(ert-deftest p3-git-run-returns-output-on-success ()
  (cl-letf (((symbol-function 'p3/git-call)
             (lambda (_directory &rest _arguments)
               '(0 . "ok\n"))))
    (should (equal (p3/git-run "/tmp" "status") "ok\n"))))

(ert-deftest p3-git-run-signals-user-error-on-failure ()
  (cl-letf (((symbol-function 'p3/git-call)
             (lambda (_directory &rest _arguments)
               '(1 . "bad\n"))))
    (should-error (p3/git-run "/tmp" "status") :type 'user-error)))

(ert-deftest p3-git-close-magit-buffers-kills-only-magit-buffers ()
  (let ((magit-a (get-buffer-create "*magit-test*"))
        (magit-b (get-buffer-create "magit-test"))
        (other (get-buffer-create "*p3-not-magit*")))
    (unwind-protect
        (progn
          (close-magit-buffers)
          (should-not (buffer-live-p magit-a))
          (should-not (buffer-live-p magit-b))
          (should (buffer-live-p other)))
      (when (buffer-live-p other) (kill-buffer other)))))
```

- [ ] **Step 2: Run Git tests and verify RED**

Expected: FAIL because `p3-git.el` does not exist.

- [ ] **Step 3: Create `p3-git.el` from the exact inline implementations**

Use:

```elisp
;;; p3-git.el --- Personal Git process helpers -*- lexical-binding: t; -*-

(require 'subr-x)

;; Move the seven approved definitions from config.org verbatim.

(provide 'p3-git)

;;; p3-git.el ends here
```

Do not alter staging behavior: config repo remains `git add -A`; notes remain `git add -u`; push remains `push --set-upstream origin HEAD`.

- [ ] **Step 4: Run Git tests and compile behavior library**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-git-test.el \
  -f ert-run-tests-batch-and-exit

emacs -Q --batch -L lisp \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile lisp/p3-git.el
```

Expected: PASS.

- [ ] **Step 5: Add failing structural tests for Git config ownership/reload wiring**

Assert `config.org` source-loads `p3-config-git`, no longer defines the seven Git functions, and `lisp/p3-config-git.el` contains:

```elisp
(p3/config-load-module 'p3-git)
```

- [ ] **Step 6: Create `p3-config-git.el`**

Use:

```elisp
;;; p3-config-git.el --- Git and Magit configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'p3-config-loader)
(p3/config-load-module 'p3-git)
```

Move verbatim:

- global `C-c C-g` binding;
- `p3/magit-command-map`;
- Magit `use-package` block;
- git-gutter-fringe+ block;
- `right-fringe-width` setting.

`close-magit-buffers` now comes from `p3-git.el`; do not redefine it here.

End with `(provide 'p3-config-git)`.

- [ ] **Step 7: Replace the Git section in `config.org`**

Keep a short explanation and:

```elisp
(p3/config-load-module 'p3-config-git)
```

- [ ] **Step 8: Run Git/config tests and compile config module**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-git-test.el \
  -l test/p3-config-test.el \
  -f ert-run-tests-batch-and-exit

emacs -Q --batch -L lisp \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile lisp/p3-config-git.el
```

Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add lisp/p3-git.el lisp/p3-config-git.el test/p3-git-test.el config.org test/p3-config-test.el
git commit -m "Extract Git behavior and configuration"
```

---

### Task 8: Extract workspace/window configuration without broadening display policy

**Files:**
- Create: `lisp/p3-config-workspace.el`
- Modify: `config.org` (`** Buffers, Windows, and Frames` plus window-related global bindings)
- Modify: `test/p3-config-test.el`

**Interfaces:**
- Consumes: `p3-commands` for buffer/window helpers.
- Produces: feature `p3-config-workspace`.

- [ ] **Step 1: Add failing structural tests**

Assert `config.org` source-loads `p3-config-workspace`, no longer defines `p3/get-local-buffer-mode` or `p3/is-current-buffer-mode-inferior-ess-r-mode`, and the workspace module contains exactly one display policy anchored on:

```elisp
(major-mode . inferior-ess-r-mode)
```

Also assert the workspace module does not introduce `python`, `vterm`, `shell-mode`, or a generic REPL pattern inside its `display-buffer-alist` rule.

- [ ] **Step 2: Verify RED**

Run the focused structural test. Expected: FAIL.

- [ ] **Step 3: Create `p3-config-workspace.el`**

Use:

```elisp
;;; p3-config-workspace.el --- Window, buffer, and navigation configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'p3-commands)
```

Move verbatim:

- transpose-frame declaration and `C-c t` binding;
- the existing `inferior-ess-r-mode` `display-buffer-alist` entry, unchanged;
- ace-window and `M-o`;
- winner mode;
- restart-emacs;
- Avy and `M-s`;
- Windows/Linux resize-window global bindings;
- `C-c k` -> `kill-buffer-and-window`;
- `C-x C-k` -> `p3/save-kill-other-buffers`.

Do not add any generic side-window behavior.

End with `(provide 'p3-config-workspace)`.

- [ ] **Step 4: Replace old workspace/window blocks in `config.org`**

At the existing Buffers/Windows/Frames location, retain concise prose and:

```elisp
(p3/config-load-module 'p3-config-workspace)
```

Delete the migrated window resize bindings from their earlier global section and the two inline buffer-mode helper definitions.

- [ ] **Step 5: Run tests and compile**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-test.el \
  -l test/p3-commands-test.el \
  -f ert-run-tests-batch-and-exit

emacs -Q --batch -L lisp \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile lisp/p3-config-workspace.el
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lisp/p3-config-workspace.el config.org test/p3-config-test.el
git commit -m "Extract workspace configuration"
```

---

### Task 9: Finish structural boundary tests, stale-bytecode regression, and CI coverage

**Files:**
- Modify: `test/p3-config-loader-test.el`
- Modify: `test/p3-config-test.el`
- Modify: `.github/workflows/emacs-tests.yml`
- Modify: `.github/workflows/windows-platform-tests.yml`

**Interfaces:**
- Consumes: all modules from Tasks 1-8.
- Produces: final architecture regression gate.

- [ ] **Step 1: Add the stale-bytecode regression test**

Add to `test/p3-config-loader-test.el` a test that creates a temporary load-path entry, byte-compiles version 1, rewrites a newer source version 2, sets `load-prefer-newer` to `t`, and verifies ordinary `require` loads version 2:

```elisp
(ert-deftest p3-config-loader-load-prefer-newer-protects-local-requires ()
  (let* ((directory (make-temp-file "p3-stale-bytecode-test-" t))
         (source (expand-file-name "p3-stale-bytecode-test-module.el" directory))
         (feature 'p3-stale-bytecode-test-module)
         (load-path (cons directory load-path))
         (load-prefer-newer t))
    (unwind-protect
        (progn
          (with-temp-file source
            (insert "(setq p3-config-loader-test--stale-value 'old)\n"
                    "(provide 'p3-stale-bytecode-test-module)\n"))
          (byte-compile-file source)
          (sleep-for 1)
          (with-temp-file source
            (insert "(setq p3-config-loader-test--stale-value 'new)\n"
                    "(provide 'p3-stale-bytecode-test-module)\n"))
          (setq features (delq feature features)
                p3-config-loader-test--stale-value nil)
          (require feature)
          (should (eq p3-config-loader-test--stale-value 'new)))
      (setq features (delq feature features))
      (delete-directory directory t))))
```

If filesystem timestamp granularity makes `sleep-for 1` insufficient on a runner, replace timing with explicit `set-file-times` on source and `.elc`; do not add retry loops.

- [ ] **Step 2: Complete architecture structural assertions**

Ensure `test/p3-config-test.el` now checks all of these in one or more focused tests:

- all five exact-source stanzas exist;
- `p3-config-editing` precedes `p3-config-completion`;
- early order is newer -> auto-compile -> secrets -> Rtools -> ordinary config modules;
- R-program and shell configuration still occur later;
- every listed moved function is absent from `config.org`;
- `p3-config-base.el` exact-source-loads `p3-commands`;
- `p3-config-git.el` exact-source-loads `p3-git`;
- `p3-commands.el` and `p3-git.el` contain no `(require 'p3-config-...` dependency;
- generated `config.el` contract still builds through `p3/config-build`;
- `.gitignore` still ignores generated `config.el` and `*.elc`.

Use string/ordering assertions, not exact line counts.

- [ ] **Step 3: Run the full local ERT suite before touching workflows**

Run:

```bash
emacs -Q --batch \
  -L lisp \
  -l test/p3-config-loader-test.el \
  -l test/p3-config-test.el \
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

Expected: all tests PASS.

- [ ] **Step 4: Byte-compile every tracked module with warnings as errors**

Run:

```bash
emacs -Q --batch \
  -L lisp \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile \
  lisp/p3-platform.el \
  lisp/p3-project.el \
  lisp/p3-config-loader.el \
  lisp/p3-core.el \
  lisp/p3-commands.el \
  lisp/p3-git.el \
  lisp/p3-config-base.el \
  lisp/p3-config-editing.el \
  lisp/p3-config-completion.el \
  lisp/p3-config-workspace.el \
  lisp/p3-config-git.el \
  lisp/p3-python.el \
  lisp/p3-terminal.el \
  lisp/p3-ess.el \
  lisp/p3-r-tools.el \
  lisp/p3-gptel.el
```

Expected: success with no warnings.

- [ ] **Step 5: Update Ubuntu workflow once**

In `.github/workflows/emacs-tests.yml`:

- add the seven new Lisp files to `Byte-compile extracted modules`;
- add `test/p3-commands-test.el` and `test/p3-git-test.el` to the ERT command;
- make no other CI expansion.

- [ ] **Step 6: Update the Windows workflow narrowly**

In `.github/workflows/windows-platform-tests.yml`:

Add PR path triggers for:

```yaml
      - "config.org"
      - "lisp/p3-commands.el"
      - "lisp/p3-git.el"
      - "lisp/p3-config-base.el"
      - "lisp/p3-config-editing.el"
      - "lisp/p3-config-completion.el"
      - "lisp/p3-config-workspace.el"
      - "lisp/p3-config-git.el"
      - "test/p3-config-test.el"
      - "test/p3-commands-test.el"
      - "test/p3-git-test.el"
```

Extend the Windows byte-compile step at minimum with:

```text
lisp/p3-commands.el
lisp/p3-git.el
```

Keep the existing loader compile/test coverage. Add `test/p3-config-test.el` to a Windows batch ERT invocation so secrets/Rtools/source-loader ordering is verified from the real repository text. Do not turn this into a broad duplicate of the Ubuntu suite.

- [ ] **Step 7: Re-run local equivalents after workflow edits**

Re-run Steps 3 and 4. Expected: PASS.

- [ ] **Step 8: Commit final gate changes**

```bash
git add test/p3-config-loader-test.el test/p3-config-test.el \
  .github/workflows/emacs-tests.yml .github/workflows/windows-platform-tests.yml
git commit -m "Verify configuration module boundaries"
```

---

### Task 10: Final review, open the PR, and use CI as the final external gate

**Files:**
- Review all changed files; modify only if the review finds a real defect.

**Interfaces:**
- Produces: a reviewable PR against `master`; no merge.

- [ ] **Step 1: Compare branch against `master`**

Run:

```bash
git diff --stat master...HEAD
git diff --check master...HEAD
git status --short
```

Expected: no whitespace errors; only intended source/tests/docs/workflow files changed; no `config.el` or `.elc` tracked.

- [ ] **Step 2: Adversarially review the final diff against the spec**

Explicitly check:

- no moved function remains duplicated inline;
- no unapproved helper was swept into `p3-commands.el` or `p3-git.el`;
- no ESS/Python/Org/terminal/GPTel redesign slipped in;
- the ESS display rule is byte-for-byte equivalent in behavior and still narrow;
- `C-c r` reaches every new `p3-config-*` source and, through base/Git config modules, the two new behavior libraries;
- early secrets override semantics are intact;
- Company configuration is unchanged;
- Git staging/push behavior is unchanged;
- config module loading uses explicit names only; there is no discovery/registry mechanism.

- [ ] **Step 3: Run the full local verification one last time**

Run the full ERT and byte-compile commands from Task 9.

Expected: PASS.

- [ ] **Step 4: Open one PR only after the branch is locally green**

Use title:

```text
Split declarative configuration into focused modules
```

PR body should summarize:

- five `p3-config-*` modules;
- `p3-commands.el` / `p3-git.el` behavior extraction;
- exact-source reload contract;
- preserved single-cache startup;
- explicit secrets/Rtools ordering;
- deferred ESS/Python/Org/etc. work;
- test coverage and no-merge-without-approval constraint.

Do not merge.

- [ ] **Step 5: Inspect exact-head Ubuntu and Windows CI once**

Expected:

- Ubuntu byte compilation succeeds;
- full ERT suite succeeds;
- Windows boundary compilation/tests succeed.

If a gate fails, fix only the root cause, rerun the narrow failing test locally where possible, push one corrective commit, and allow CI to rerun. After two unproductive attempts on the same failure mode, change diagnostic strategy rather than adding diagnostic machinery.

- [ ] **Step 6: Final PR review and handoff**

Report:

- exact branch/HEAD SHA;
- changed-file count;
- exact-head CI results;
- any non-blocking observations;
- recommendation on squash merge.

Wait for explicit merge approval.
