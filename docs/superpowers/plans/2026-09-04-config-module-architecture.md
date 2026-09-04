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

- `lisp/p3-config-base.el` — broad global configuration: dashboard, which-key wiring, package-update UI, fonts/cursor, process/session defaults, backups/autosaves, global modes, line numbers, trash, async/Dired, and basic global UI bindings. Exact-source-loads `p3-commands.el`.
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
- `test/p3-config-loader-test.el` — exact-source loader, behavior-owner reload, and stale-bytecode tests.
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

Append to `test/p3-config-loader-test.el`:

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

- [ ] **Step 2: Run loader tests and verify RED**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-loader-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: FAIL because the new loader API does not exist.

- [ ] **Step 3: Implement the exact-source loader**

Add near the existing path constants in `lisp/p3-config-loader.el`:

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

Run the Step 2 command. Expected: PASS.

- [ ] **Step 5: Add a real `p3/config-reload` integration test**

Append to `test/p3-core-test.el`:

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

- [ ] **Step 6: Run core tests and compile the loader**

```bash
emacs -Q --batch -L lisp -l test/p3-core-test.el -f ert-run-tests-batch-and-exit
emacs -Q --batch -L lisp \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile lisp/p3-config-loader.el
```

Expected: PASS with no compile warnings.

- [ ] **Step 7: Commit**

```bash
git add lisp/p3-config-loader.el test/p3-config-loader-test.el test/p3-core-test.el
git commit -m "Add exact-source config module loading"
```

---

### Task 2: Lock down early orchestration ordering before extracting domains

**Files:**
- Modify: `config.org` (`* Startup` auto-compile/secrets/platform blocks)
- Modify: `test/p3-config-test.el`

**Interfaces:**
- Produces: explicit order `load-prefer-newer` -> auto-compile -> secrets -> Rtools/MSYS2. R-program and shell configuration remain later.

- [ ] **Step 1: Add a failing structural order test**

```elisp
(ert-deftest p3-config-early-orchestration-order-is-explicit ()
  (with-temp-buffer
    (insert-file-contents (expand-file-name "config.org" p3-config-test--root))
    (goto-char (point-min))
    (let ((newer (progn
                   (should (search-forward "(setq load-prefer-newer t)" nil t))
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

- [ ] **Step 2: Run the focused test and verify RED**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-test.el \
  --eval '(ert-run-tests-batch-and-exit "p3-config-early-orchestration-order-is-explicit")'
```

Expected: FAIL because the current auto-compile block sets `load-prefer-newer` after activating auto-compile.

- [ ] **Step 3: Reorder only the early bootstrap forms**

Use this shape in `config.org`:

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

- [ ] **Step 4: Run all config structural/build tests**

```bash
emacs -Q --batch -L lisp -l test/p3-config-test.el -f ert-run-tests-batch-and-exit
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

**Interfaces:**
- Produces exactly: `p3/keybinding-sections`, `p3/keybinding-atlas`, `p3/save-kill-other-buffers`, `p3/sudo-edit`, `p3/region-suffix`, `p3/newline-after-comma-or-space`, `p3/force-quotes`, `p3/byte-compile-init-dir`, `p3/windows-shell`, `move-line`, `move-line-up`, `move-line-down`, `p3/open-in-external-app`, `check-curl-version`, `p3/get-local-buffer-mode`, and `p3/is-current-buffer-mode-inferior-ess-r-mode`.

- [ ] **Step 1: Create failing command tests**

Create `test/p3-commands-test.el` with repository load-path boilerplate and:

```elisp
(require 'ert)
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

On non-Windows, omit `p3/windows-shell` from the command list if its original platform guard is preserved. On Windows, assert it is a command.

- [ ] **Step 2: Run and verify RED**

```bash
emacs -Q --batch -L lisp -l test/p3-commands-test.el -f ert-run-tests-batch-and-exit
```

Expected: FAIL because `p3-commands.el` does not exist.

- [ ] **Step 3: Create `p3-commands.el`**

Use:

```elisp
;;; p3-commands.el --- Generic personal interactive commands -*- lexical-binding: t; -*-

(require 'subr-x)
(declare-function dired-get-marked-files "dired" (&optional localp arg filter distinguish-one-marked error))
(declare-function w32-shell-execute "w32fns" (operation document &optional parameters show-flag))

;; Insert, unchanged, the exact current definitions/data named in this task.

(provide 'p3-commands)

;;; p3-commands.el ends here
```

Copy those definitions verbatim from `config.org`; do not rename, simplify regexes, alter prompts, change external-open OS branches, or change the Windows-only definition guard for `p3/windows-shell`.

- [ ] **Step 4: Run tests and byte-compile**

```bash
emacs -Q --batch -L lisp -l test/p3-commands-test.el -f ert-run-tests-batch-and-exit
emacs -Q --batch -L lisp \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile lisp/p3-commands.el
```

Expected: PASS with no warnings.

- [ ] **Step 5: Commit**

```bash
git add lisp/p3-commands.el test/p3-commands-test.el
git commit -m "Extract generic personal commands"
```

---

### Task 4: Create the base configuration module and remove migrated base implementation

**Files:**
- Create: `lisp/p3-config-base.el`
- Modify: `config.org` (`* Startup`, `* General`, `* Global settings`, generic `* Functions` blocks)
- Modify: `test/p3-config-test.el`

**Interfaces:**
- Consumes: `p3/config-load-module` and `p3-commands`.
- Produces: feature `p3-config-base`; exact-source-loads `p3-commands` on every config reload.

- [ ] **Step 1: Add failing base ownership tests**

Assert `config.org` contains:

```elisp
(p3/config-load-module 'p3-config-base)
```

and no longer contains inline definitions for `p3/keybinding-sections`, `p3/keybinding-atlas`, or the generic functions moved to `p3-commands.el`. Also read `lisp/p3-config-base.el` and assert it contains:

```elisp
(p3/config-load-module 'p3-commands)
```

- [ ] **Step 2: Verify RED**

Run the focused structural test. Expected: FAIL.

- [ ] **Step 3: Create `p3-config-base.el`**

Start with:

```elisp
;;; p3-config-base.el --- Broad global configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'p3-config-loader)
(p3/config-load-module 'p3-commands)
```

Move the current blocks, preserving forms and values, for:

- fullscreen default frame;
- dashboard;
- which-key and `C-c ?` atlas wiring;
- package declaration and `p3/package-update`;
- fonts/cursor;
- y/n prompt advice and process-kill prompt glue;
- Comint scroll defaults and scrolling settings;
- delete-by-trash;
- async Dired/package processing;
- global font lock and auto-revert;
- line-number helper and activation;
- backup/autosave directories and version settings;
- Dired;
- all-the-icons / all-the-icons-dired;
- font-scale bindings;
- Windows-only `C-x C-i` binding for `p3/windows-shell`.

Do not move `load-prefer-newer`, auto-compile activation, secrets, or platform activation into this module.

End with:

```elisp
(provide 'p3-config-base)

;;; p3-config-base.el ends here
```

- [ ] **Step 4: Replace migrated `config.org` blocks with a concise Base section**

Immediately after early orchestration, use short prose plus:

```elisp
(p3/config-load-module 'p3-config-base)
```

Delete moved function bodies. For extracted commands whose bindings are owned by later tasks, temporarily leave only their binding forms. Keep the existing `p3-core` stanza in `config.org`.

- [ ] **Step 5: Run config/core/command tests and compile base**

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

- [ ] **Step 1: Add failing completion ownership tests**

Assert `config.org` contains:

```elisp
(p3/config-load-module 'p3-config-completion)
```

and no longer contains inline `p3/consult-r-doc-chapter-search`, `p3/consult-line-all`, `p3/ess-company-config`, `p3/r-company-backends`, `use-package vertico`, or `use-package company`.

- [ ] **Step 2: Verify RED**

Run the focused structural test. Expected: FAIL.

- [ ] **Step 3: Create `p3-config-completion.el`**

Start with:

```elisp
;;; p3-config-completion.el --- Completion and search configuration -*- lexical-binding: t; -*-

(require 'use-package)

(declare-function consult-line "consult" (&optional initial start))
(declare-function consult-line-multi "consult" (query &optional initial))
(declare-function consult-ripgrep "consult" (&optional directory initial))
```

Move verbatim:

- savehist;
- Vertico;
- Orderless;
- Marginalia;
- Consult helper declarations/functions and Consult block;
- Embark and embark-consult;
- Company including `p3/r-company-backends`, `p3/ess-company-config`, and `company-dabbrev-downcase`.

Do not move synosaurus or yasnippet. End with `(provide 'p3-config-completion)`.

- [ ] **Step 4: Replace the inline completion block**

At the current completion section position, retain short prose plus:

```elisp
(p3/config-load-module 'p3-config-completion)
```

Keep this before ESS so the existing ESS Company hook still resolves.

- [ ] **Step 5: Test and compile**

```bash
emacs -Q --batch -L lisp -l test/p3-config-test.el -f ert-run-tests-batch-and-exit
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
- Modify: `config.org` (`* General`, `* Global settings`, `** Editing-related`, `** Multiple cursors`)
- Modify: `test/p3-config-test.el`

**Interfaces:**
- Consumes: `p3-commands` (already exact-source-reloaded by base during `C-c r`).
- Produces: feature `p3-config-editing`.

- [ ] **Step 1: Add failing editing order/ownership tests**

Assert both module stanzas exist and editing loads before completion:

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

Run the focused structural test. Expected: FAIL.

- [ ] **Step 3: Create `p3-config-editing.el`**

Start with:

```elisp
;;; p3-config-editing.el --- Generic editing configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'p3-commands)
```

Move, preserving current settings/bindings:

- delete-selection;
- before-save whitespace cleanup;
- CUA and `cua-auto-tabify-rectangles`;
- `indent-tabs-mode` default;
- default Cyrillic transliteration input method;
- smartparens;
- global compile binding and disabled suspend binding;
- current initial regex-aware isearch bindings;
- `C-c a` align-region lambda;
- extracted-command bindings `C-c s`, `C-c C-SPC`, `C-c q`, `M-<up>`, `M-<down>`;
- google-this;
- wgrep;
- undo-tree;
- super-save;
- multiple-cursors.

Load this module at the early general/global editing position before completion. This preserves the final Consult `C-s` / `C-r` bindings because completion still loads afterward.

End with `(provide 'p3-config-editing)`.

- [ ] **Step 4: Replace corresponding inline blocks**

Use concise prose plus:

```elisp
(p3/config-load-module 'p3-config-editing)
```

Remove the temporary generic command binding forms left by Task 4.

- [ ] **Step 5: Test and compile**

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

- [ ] **Step 1: Create failing Git behavior tests**

Create `test/p3-git-test.el` with normal repository load-path boilerplate and:

```elisp
(require 'ert)
(require 'cl-lib)
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

- [ ] **Step 2: Verify RED**

```bash
emacs -Q --batch -L lisp -l test/p3-git-test.el -f ert-run-tests-batch-and-exit
```

Expected: FAIL because `p3-git.el` does not exist.

- [ ] **Step 3: Create `p3-git.el`**

Start with:

```elisp
;;; p3-git.el --- Personal Git process helpers -*- lexical-binding: t; -*-

(require 'subr-x)
```

Move the seven approved definitions verbatim from `config.org`. Do not alter staging behavior: config repo remains `git add -A`; notes remain `git add -u`; push remains `push --set-upstream origin HEAD`. End with `(provide 'p3-git)`.

- [ ] **Step 4: Test and compile behavior library**

```bash
emacs -Q --batch -L lisp -l test/p3-git-test.el -f ert-run-tests-batch-and-exit
emacs -Q --batch -L lisp \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile lisp/p3-git.el
```

Expected: PASS.

- [ ] **Step 5: Add failing Git config structural tests**

Assert `config.org` source-loads `p3-config-git`, no longer defines the seven Git functions, and `lisp/p3-config-git.el` contains:

```elisp
(p3/config-load-module 'p3-git)
```

- [ ] **Step 6: Create `p3-config-git.el`**

Start with:

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

Do not redefine `close-magit-buffers` here. End with `(provide 'p3-config-git)`.

- [ ] **Step 7: Replace the Git section**

Use short prose plus:

```elisp
(p3/config-load-module 'p3-config-git)
```

- [ ] **Step 8: Test and compile**

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
- Modify: `config.org` (`** Buffers, Windows, and Frames` and window-related global bindings)
- Modify: `test/p3-config-test.el`

**Interfaces:**
- Consumes: `p3-commands` for buffer/window helpers.
- Produces: feature `p3-config-workspace`.

- [ ] **Step 1: Add failing workspace structural tests**

Assert `config.org` source-loads `p3-config-workspace`, no longer defines `p3/get-local-buffer-mode` or `p3/is-current-buffer-mode-inferior-ess-r-mode`, and the module contains the existing anchor:

```elisp
(major-mode . inferior-ess-r-mode)
```

Also assert its display policy does not add `python`, `vterm`, `shell-mode`, or a generic REPL matcher.

- [ ] **Step 2: Verify RED**

Run the focused structural test. Expected: FAIL.

- [ ] **Step 3: Create `p3-config-workspace.el`**

Start with:

```elisp
;;; p3-config-workspace.el --- Window, buffer, and navigation configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'p3-commands)
```

Move verbatim:

- transpose-frame and `C-c t`;
- the existing `inferior-ess-r-mode` `display-buffer-alist` entry, unchanged;
- ace-window and `M-o`;
- winner;
- restart-emacs;
- Avy and `M-s`;
- Windows/Linux resize-window bindings;
- `C-c k` -> `kill-buffer-and-window`;
- `C-x C-k` -> `p3/save-kill-other-buffers`.

Do not add any generic side-window behavior. End with `(provide 'p3-config-workspace)`.

- [ ] **Step 4: Replace old workspace/window blocks**

At the existing Buffers/Windows/Frames location, retain short prose plus:

```elisp
(p3/config-load-module 'p3-config-workspace)
```

Delete migrated window resize bindings from the earlier global section and delete the two inline buffer-mode helper definitions.

- [ ] **Step 5: Test and compile**

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

### Task 9: Finish reload, stale-bytecode, architecture, and CI regression gates

**Files:**
- Modify: `test/p3-config-loader-test.el`
- Modify: `test/p3-config-test.el`
- Modify: `.github/workflows/emacs-tests.yml`
- Modify: `.github/workflows/windows-platform-tests.yml`

**Interfaces:**
- Consumes: all modules from Tasks 1-8.
- Produces: final architecture/reload regression gate.

- [ ] **Step 1: Add owner-pattern reload tests for both new behavior libraries**

The production base/Git modules are declarative and package-heavy, so test their reload mechanism in isolation with temporary owner modules using the same filenames and exact pattern. Add a helper to `test/p3-config-loader-test.el`:

```elisp
(defun p3-config-loader-test--write-owned-module
    (directory owner behavior value)
  "Write OWNER that exact-source-loads BEHAVIOR setting VALUE."
  (with-temp-file (expand-file-name (format "%s.el" behavior) directory)
    (insert (format "(setq p3-config-loader-test--owned-value '%s)\n" value)
            (format "(provide '%s)\n" behavior)))
  (with-temp-file (expand-file-name (format "%s.el" owner) directory)
    (insert "(require 'p3-config-loader)\n"
            (format "(p3/config-load-module '%s)\n" behavior)
            (format "(provide '%s)\n" owner))))
```

Then test the two approved owner pairs:

```elisp
(ert-deftest p3-config-loader-base-owner-reloads-p3-commands ()
  (let* ((directory (make-temp-file "p3-owner-reload-test-" t))
         (p3/config-lisp-directory directory))
    (unwind-protect
        (progn
          (p3-config-loader-test--write-owned-module
           directory 'p3-config-base 'p3-commands 'one)
          (p3/config-load-module 'p3-config-base)
          (should (eq p3-config-loader-test--owned-value 'one))
          (p3-config-loader-test--write-owned-module
           directory 'p3-config-base 'p3-commands 'two)
          (p3/config-load-module 'p3-config-base)
          (should (eq p3-config-loader-test--owned-value 'two)))
      (dolist (feature '(p3-config-base p3-commands))
        (setq features (delq feature features)))
      (delete-directory directory t))))

(ert-deftest p3-config-loader-git-owner-reloads-p3-git ()
  (let* ((directory (make-temp-file "p3-owner-reload-test-" t))
         (p3/config-lisp-directory directory))
    (unwind-protect
        (progn
          (p3-config-loader-test--write-owned-module
           directory 'p3-config-git 'p3-git 'one)
          (p3/config-load-module 'p3-config-git)
          (should (eq p3-config-loader-test--owned-value 'one))
          (p3-config-loader-test--write-owned-module
           directory 'p3-config-git 'p3-git 'two)
          (p3/config-load-module 'p3-config-git)
          (should (eq p3-config-loader-test--owned-value 'two)))
      (dolist (feature '(p3-config-git p3-git))
        (setq features (delq feature features)))
      (delete-directory directory t))))
```

Combined with structural tests that production `p3-config-base.el` and `p3-config-git.el` contain the same exact-source owner calls, these tests cover the approved reload contract without loading external packages in ERT.

- [ ] **Step 2: Add the stale-bytecode regression test**

```elisp
(ert-deftest p3-config-loader-load-prefer-newer-protects-local-requires ()
  (let* ((directory (make-temp-file "p3-stale-bytecode-test-" t))
         (source (expand-file-name "p3-stale-bytecode-test-module.el" directory))
         (compiled (concat source "c"))
         (feature 'p3-stale-bytecode-test-module)
         (load-path (cons directory load-path))
         (load-prefer-newer t))
    (unwind-protect
        (progn
          (with-temp-file source
            (insert "(setq p3-config-loader-test--stale-value 'old)\n"
                    "(provide 'p3-stale-bytecode-test-module)\n"))
          (byte-compile-file source)
          (with-temp-file source
            (insert "(setq p3-config-loader-test--stale-value 'new)\n"
                    "(provide 'p3-stale-bytecode-test-module)\n"))
          (set-file-times compiled (seconds-to-time 1000000000))
          (set-file-times source (seconds-to-time 2000000000))
          (setq features (delq feature features)
                p3-config-loader-test--stale-value nil)
          (require feature)
          (should (eq p3-config-loader-test--stale-value 'new)))
      (setq features (delq feature features))
      (delete-directory directory t))))
```

- [ ] **Step 3: Complete architecture structural assertions**

Ensure `test/p3-config-test.el` checks:

- all five exact-source config-module stanzas exist;
- `p3-config-editing` precedes `p3-config-completion`;
- early order is newer -> auto-compile -> secrets -> Rtools -> ordinary config modules;
- R-program and shell configuration still occur later;
- every listed moved function is absent from `config.org`;
- `p3-config-base.el` exact-source-loads `p3-commands`;
- `p3-config-git.el` exact-source-loads `p3-git`;
- `p3-commands.el` and `p3-git.el` contain no dependency on `p3-config-*`;
- the real config still builds through `p3/config-build`;
- generated `config.el` and `*.elc` remain ignored/untracked.

Use string/ordering assertions, not exact line counts.

- [ ] **Step 4: Run the full local ERT suite**

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

- [ ] **Step 5: Byte-compile every tracked module with warnings as errors**

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

- [ ] **Step 6: Update the Ubuntu workflow once**

In `.github/workflows/emacs-tests.yml`, add the seven new Lisp files to byte compilation and add `test/p3-commands-test.el` plus `test/p3-git-test.el` to the ERT command. Make no other CI expansion.

- [ ] **Step 7: Update the Windows workflow narrowly**

Add PR path triggers for `config.org`, all new local modules, `test/p3-config-test.el`, `test/p3-commands-test.el`, and `test/p3-git-test.el`. Extend Windows byte compilation at minimum with `lisp/p3-commands.el` and `lisp/p3-git.el`. Keep existing config-loader coverage and run `test/p3-config-test.el` on Windows so the real secrets/Rtools/source-loader ordering is checked. Do not duplicate the full Ubuntu suite.

- [ ] **Step 8: Re-run local full ERT and byte compilation after workflow edits**

Run Steps 4 and 5 again. Expected: PASS.

- [ ] **Step 9: Commit final gate changes**

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

```bash
git diff --stat master...HEAD
git diff --check master...HEAD
git status --short
```

Expected: no whitespace errors; only intended source/tests/docs/workflow files changed; no `config.el` or `.elc` tracked.

- [ ] **Step 2: Adversarially review the final diff against the spec**

Check explicitly:

- no moved function remains duplicated inline;
- no unapproved helper was swept into `p3-commands.el` or `p3-git.el`;
- no ESS/Python/Org/terminal/GPTel redesign slipped in;
- the ESS display rule is behaviorally unchanged and still narrow;
- `C-c r` reaches all five new config-module sources and, through base/Git owner modules, both new behavior libraries;
- secrets-based Rtools overrides remain effective;
- Company configuration is unchanged;
- Git staging/push behavior is unchanged;
- local config module loading uses explicit names only; there is no registry/discovery layer.

- [ ] **Step 3: Run the full local gate one last time**

Run Task 9 Steps 4 and 5. Expected: PASS.

- [ ] **Step 4: Open one PR only after the branch is locally green**

Use title:

```text
Split declarative configuration into focused modules
```

The PR body must state: five `p3-config-*` modules; `p3-commands.el` / `p3-git.el` extraction; exact-source reload contract; preserved single-cache startup; explicit secrets/Rtools ordering; deferred ESS/Python/Org/etc. work; verification performed; and no merge without explicit approval.

- [ ] **Step 5: Inspect exact-head Ubuntu and Windows CI**

Expected: Ubuntu byte compilation and full ERT succeed; Windows boundary compilation/config tests succeed.

If a gate fails, fix the root cause, run the narrow failing test locally where possible, push one corrective commit, and allow CI to rerun. After two unproductive attempts on the same failure mode, switch diagnostic strategy rather than adding diagnostic machinery.

- [ ] **Step 6: Final PR review and handoff**

Report exact branch/HEAD SHA, changed-file count, exact-head CI results, any non-blocking observations, and the recommended merge method. Wait for explicit merge approval.
