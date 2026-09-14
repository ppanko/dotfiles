# Unified Project-Aware Bash Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Linux-only vterm stack with one project-aware Bash workflow built on `shell-mode`/Comint and use that same workflow on native Windows without disturbing the existing Rtools/MSYS2 shell behavior.

**Architecture:** `p3-platform.el` remains the authority for platform shell discovery and exposes the Bash program used by the project shell. `p3-terminal.el` owns only project-root/session behavior and launches ordinary `shell-mode` buffers. `p3-config-terminal.el` wires the same commands and bindings on Linux and Windows; vterm/ble.sh-specific configuration is removed.

**Tech Stack:** Emacs Lisp, built-in `shell-mode`/Comint, `project.el`, ERT, GitHub Actions on Ubuntu and native Windows.

**Spec:** `docs/superpowers/specs/2026-09-14-unified-project-bash-design.md`

## Global Constraints

- Preserve the current Windows Rtools/MSYS2 discovery, PATH mutation, `--login` Bash arguments, CRLF stripping, and UTF-8 process coding unless a focused regression requires a correction.
- Use Bash on GNU/Linux and native Windows; do not add WSL, Git Bash, PowerShell, Eat, vterm, or another terminal backend.
- Keep project identity in `project.el`; use local `default-directory` only when there is no project.
- Reject remote/TRAMP-only roots rather than launching a local Bash with a remote working directory.
- Keep at most one ephemeral primary-shell mapping per normalized root; extra sessions are ordinary shell buffers.
- Remove obsolete vterm/ble.sh machinery rather than preserving compatibility aliases without a real consumer.
- Do not test Comint internals; test only P3-owned root/session/configuration behavior.

---

### Task 1: Define the cross-platform project-shell contract in tests

**Files:**
- Modify: `test/p3-terminal-test.el`
- Modify: `test/p3-config-terminal-test.el`
- Modify: `test/p3-platform-test.el`

**Interfaces:**
- Consumes: existing `p3/project-root`, Windows shell configuration in `p3-platform.el`.
- Produces: executable expectations for `p3/platform-bash-program`, `p3/project-shell-root`, `p3/project-shell-buffer-name`, `p3/project-shell-buffer`, `p3/project-shell`, `p3/project-shell-new`, `p3/project-shell-switch`, `p3/project-shell-other-window`, `p3/project-shell-rename`, `p3/project-shell-kill`, and `p3/project-shell-command-map`.

- [ ] **Step 1: Rewrite the terminal tests around generic project-shell behavior**

Replace vterm-specific assertions with tests equivalent to:

```elisp
(ert-deftest p3-terminal-buffer-name-is-stable-and-root-specific ()
  (let ((first (p3/project-shell-buffer-name "/tmp/project-a/"))
        (again (p3/project-shell-buffer-name "/tmp/project-a/"))
        (second (p3/project-shell-buffer-name "/tmp/project-b/")))
    (should (equal first again))
    (should-not (equal first second))
    (should (string-match-p
             "\\`\\*shell:project-a:[[:xdigit:]]\\{6\\}\\*\\'" first))))

(ert-deftest p3-terminal-root-prefers-project-root ()
  (let ((default-directory "/tmp/fallback/"))
    (cl-letf (((symbol-function 'p3/project-root)
               (lambda () "/tmp/project/")))
      (should (equal (p3/project-shell-root) "/tmp/project/")))))

(ert-deftest p3-terminal-root-rejects-remote-fallback ()
  (let ((default-directory "/ssh:host:/tmp/project/"))
    (cl-letf (((symbol-function 'p3/project-root) (lambda () nil)))
      (should-error (p3/project-shell-root) :type 'user-error))))
```

Add behavioral tests that stub the shell starter and prove:

```elisp
(ert-deftest p3-terminal-primary-shell-is-reused-per-root ()
  ;; Stub p3/project-shell--start so no real subprocess is created.
  ;; Two calls for the same root must return the same live buffer.
  ;; A different root must return a different buffer.
  )

(ert-deftest p3-terminal-extra-session-does-not-replace-primary ()
  ;; Create primary -> create NEW-SESSION -> request primary again.
  ;; The final primary must equal the first buffer, not the extra buffer.
  )

(ert-deftest p3-terminal-shell-starts-with-root-as-default-directory ()
  ;; Capture default-directory inside p3/project-shell--start and assert root.
  )

(ert-deftest p3-terminal-stale-primary-is-replaced ()
  ;; Seed mapping with a killed buffer, then assert a new buffer is created.
  )
```

Keep the command-map test but require keys `t n s o r k` to resolve to the new project-shell commands; drop the vterm-only copy/maximize requirements unless current usage proves they are still needed.

- [ ] **Step 2: Rewrite terminal configuration ownership tests**

Replace the platform split/vterm form assertion with exact shared binding expectations:

```elisp
(ert-deftest p3-config-terminal-uses-one-project-shell-surface ()
  (let ((forms (p3-config-terminal-test--forms)))
    (should (member '(p3/windows-configure-shell) forms))
    (should (member '(global-set-key (kbd "C-x C-u") #'p3/project-shell) forms))
    (should (member '(keymap-global-set "C-c T" p3/project-shell-command-map) forms))
    (should-not (seq-some
                 (lambda (form)
                   (string-match-p "vterm" (prin1-to-string form)))
                 forms))))
```

Update the `config.org` ownership test so `use-package vterm` remains forbidden and no vterm-specific symbols are expected in the terminal config.

- [ ] **Step 3: Add platform Bash resolver tests without changing Windows behavior**

Add:

```elisp
(ert-deftest p3-platform-bash-program-uses-rtools-bash-on-windows ()
  (let* ((root (make-temp-file "p3-platform-bash-" t))
         (linuxy-environment-path (file-name-as-directory root))
         (bash (expand-file-name "bash.exe" root)))
    (unwind-protect
        (progn
          (with-temp-file bash)
          (cl-letf (((symbol-function 'p3/windows-p) (lambda () t)))
            (should (equal (p3/platform-bash-program) bash))))
      (delete-directory root t))))

(ert-deftest p3-platform-bash-program-uses-executable-find-on-linux ()
  (cl-letf (((symbol-function 'p3/windows-p) (lambda () nil))
            ((symbol-function 'executable-find)
             (lambda (name) (and (equal name "bash") "/usr/bin/bash"))))
    (should (equal (p3/platform-bash-program) "/usr/bin/bash"))))
```

Keep the existing Windows `p3/windows-configure-shell` and CRLF/coding tests unchanged as regression coverage.

- [ ] **Step 4: Run focused tests and confirm RED**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-platform-test.el \
  -l test/p3-terminal-test.el \
  -l test/p3-config-terminal-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: failures only for the new project-shell/Bash-resolver contract; unrelated existing tests remain green.

- [ ] **Step 5: Commit the RED contract**

```bash
git add test/p3-platform-test.el test/p3-terminal-test.el test/p3-config-terminal-test.el
git commit -m "test: define unified project Bash workflow"
```

---

### Task 2: Add the platform Bash resolver and project-shell behavior

**Files:**
- Modify: `lisp/p3-platform.el`
- Replace/refactor: `lisp/p3-terminal.el`
- Test: `test/p3-platform-test.el`
- Test: `test/p3-terminal-test.el`

**Interfaces:**
- Consumes: `p3/project-root`, `linuxy-environment-path`, `shell`, `shell-mode`/Comint.
- Produces: `p3/platform-bash-program` and the public `p3/project-shell-*` API defined in Task 1.

- [ ] **Step 1: Add the smallest platform Bash resolver**

Implement in `p3-platform.el`:

```elisp
(defun p3/platform-bash-program ()
  "Return the Bash executable for the current supported platform."
  (let ((program
         (if (p3/windows-p)
             (and linuxy-environment-path
                  (let ((candidate
                         (expand-file-name "bash.exe"
                                           linuxy-environment-path)))
                    (and (file-regular-p candidate) candidate)))
           (executable-find "bash"))))
    (or program
        (user-error "Bash is unavailable for the current platform setup"))))
```

Do not alter `p3/windows-configure-shell` while its regression tests remain green.

- [ ] **Step 2: Replace vterm-specific state/helpers with generic shell helpers**

In `p3-terminal.el`, remove ble.sh constants/bootstrap, vterm prerequisite checks, vterm API declarations, copy-mode setup, and `p3/vterm-*` functions.

Add:

```elisp
(defvar p3/project-shell-buffers (make-hash-table :test #'equal)
  "Map normalized roots to their primary P3 shell buffers.")

(defun p3/project-shell-root ()
  "Return the local project root or local current directory."
  (let ((root (or (p3/project-root) default-directory)))
    (when (file-remote-p root)
      (user-error "Project shell requires a local project or directory"))
    (file-name-as-directory (expand-file-name root))))

(defun p3/project-shell-buffer-name (root)
  "Return a stable primary shell buffer name for ROOT."
  (format "*shell:%s:%s*"
          (file-name-nondirectory (directory-file-name root))
          (substring (secure-hash 'sha1 root) 0 6)))
```

- [ ] **Step 3: Add one isolated shell starter**

Use one internal function so tests can stub process creation:

```elisp
(defun p3/project-shell--start (buffer root)
  "Start Bash in BUFFER at ROOT and return BUFFER."
  (let ((default-directory root)
        (explicit-shell-file-name (p3/platform-bash-program)))
    (shell (buffer-name buffer)))
  (get-buffer (buffer-name buffer)))
```

If `shell` replaces the pre-created buffer rather than reusing it, adjust the helper so it passes the intended name directly to `shell`; keep all process-start details inside this function.

- [ ] **Step 4: Implement primary reuse and explicit extra sessions**

Implement `p3/project-shell-buffer` so:

```elisp
(defun p3/project-shell-buffer (&optional new-session)
  ;; resolve root
  ;; return live mapped primary when NEW-SESSION is nil
  ;; otherwise create a primary-name or generate-new-buffer-name
  ;; start the shell with root bound as default-directory
  ;; map only the primary path
  )
```

When a mapped buffer is dead, remove/replace it lazily. Do not add a persistent session registry.

- [ ] **Step 5: Implement the public commands and command map**

Add the six approved commands and:

```elisp
(defvar-keymap p3/project-shell-command-map
  :doc "Commands for project-aware Bash shells."
  "t" #'p3/project-shell
  "n" #'p3/project-shell-new
  "s" #'p3/project-shell-switch
  "o" #'p3/project-shell-other-window
  "r" #'p3/project-shell-rename
  "k" #'p3/project-shell-kill)
```

`p3/project-shell` should retain the useful existing toggle behavior: if invoked from a P3 shell with no prefix argument, switch back to the previous buffer; with a prefix argument, create a new session.

- [ ] **Step 6: Run focused behavior tests and make them GREEN**

Run the Task 1 focused ERT command. Expected: all platform and terminal behavior tests pass; config tests may remain red until Task 3.

- [ ] **Step 7: Commit behavior implementation**

```bash
git add lisp/p3-platform.el lisp/p3-terminal.el test/p3-platform-test.el test/p3-terminal-test.el
git commit -m "feat: add cross-platform project Bash shells"
```

---

### Task 3: Rewire terminal configuration and remove vterm/ble.sh

**Files:**
- Modify: `lisp/p3-config-terminal.el`
- Delete: `vterm-bashrc`
- Modify: `test/p3-config-terminal-test.el`
- Modify: `test/p3-config-terminal-windows-test.el` only if its smoke contract names vterm/old bindings
- Modify: `.github/workflows/emacs-tests.yml`

**Interfaces:**
- Consumes: `p3/project-shell`, `p3/project-shell-command-map`, existing `p3/windows-configure-shell`.
- Produces: the same shell entry points/bindings on Linux and Windows with no vterm dependency.

- [ ] **Step 1: Simplify `p3-config-terminal.el` to shared wiring**

The final module should reduce to the equivalent of:

```elisp
(require 'use-package)
(require 'p3-config-loader)

(defvar p3/project-shell-command-map)
(declare-function p3/windows-configure-shell "p3-platform" ())
(declare-function p3/project-shell "p3-terminal" (&optional new-session))

(p3/config-load-module 'p3-terminal)
(p3/windows-configure-shell)

(global-set-key (kbd "C-x C-u") #'p3/project-shell)
(keymap-global-set "C-c T" p3/project-shell-command-map)
```

Remove the GNU/Linux-only `use-package vterm` block and all vterm variables/declarations.

- [ ] **Step 2: Delete vterm-only Bash startup and ble.sh ownership**

Delete `vterm-bashrc`. Verify repository search has no live references to `P3_BLESH_FILE`, `p3/blesh-*`, `p3/vterm-*`, `vterm-shell`, or `vterm-copy-mode` outside historical docs/specs.

Run:

```bash
git grep -nE 'P3_BLESH_FILE|p3/blesh-|p3/vterm-|vterm-shell|vterm-copy-mode' -- ':!docs/superpowers/*'
```

Expected: no supported-code references.

- [ ] **Step 3: Update Linux smoke assertion**

Change the terminal smoke gate in `.github/workflows/emacs-tests.yml` to assert the new boundary, for example:

```elisp
(unless (and (featurep 'p3-config-terminal)
             (featurep 'p3-terminal)
             (keymapp p3/project-shell-command-map)
             (eq (key-binding (kbd "C-x C-u")) #'p3/project-shell))
  (kill-emacs 1))
```

Do not add real shell subprocess execution to the headless smoke step.

- [ ] **Step 4: Run focused config tests and byte compilation**

Run:

```bash
emacs -Q --batch -L lisp \
  --eval '(require (quote use-package-ensure))' \
  --eval '(setq use-package-ensure-function (lambda (&rest _) t))' \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile \
  lisp/p3-platform.el lisp/p3-terminal.el lisp/p3-config-terminal.el

emacs -Q --batch -L lisp \
  -l test/p3-platform-test.el \
  -l test/p3-terminal-test.el \
  -l test/p3-config-terminal-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: compilation succeeds with warnings treated as errors and focused ERT is fully green.

- [ ] **Step 5: Commit configuration cleanup**

```bash
git add lisp/p3-config-terminal.el test/p3-config-terminal-test.el .github/workflows/emacs-tests.yml
git rm vterm-bashrc
git commit -m "refactor: replace vterm with project shell-mode workflow"
```

---

### Task 4: Add native-Windows execution coverage and final regression gates

**Files:**
- Modify: `.github/workflows/windows-platform-tests.yml`
- Modify: `test/p3-config-terminal-windows-test.el` if needed for the new shared boundary
- Modify: `test/p3-terminal-test.el` only for platform-neutral defects exposed by native Windows

**Interfaces:**
- Consumes: all project-shell/platform interfaces from Tasks 1-3.
- Produces: CI coverage proving `p3-terminal.el` and its tests are actually exercised under native Windows.

- [ ] **Step 1: Make the Windows workflow watch and compile the shared terminal module**

Add these path filters if absent:

```yaml
      - "lisp/p3-terminal.el"
      - "test/p3-terminal-test.el"
```

Add `lisp/p3-terminal.el` to the native-Windows byte-compilation command.

- [ ] **Step 2: Run the shared terminal tests on native Windows**

Add `-l test/p3-terminal-test.el` to the existing Windows platform/project test invocation so the same project-root/session contract runs under Windows Emacs.

Keep `test/p3-config-terminal-windows-test.el` as the smoke boundary for loading the actual Windows terminal configuration.

- [ ] **Step 3: Verify Windows smoke expectations target Bash/project integration**

The Windows smoke test should prove at least:

```elisp
(should (featurep 'p3-terminal))
(should (keymapp p3/project-shell-command-map))
(should (eq (key-binding (kbd "C-x C-u")) #'p3/project-shell))
```

Retain existing assertions that protect Rtools/MSYS2 selection and CRLF/coding behavior where they already live.

- [ ] **Step 4: Run the complete Linux suite locally or through the workflow command**

Run the repository's full ERT command from `.github/workflows/emacs-tests.yml` and the strict byte-compilation command. Expected: 0 unexpected ERT results and no byte-compile warnings/errors.

- [ ] **Step 5: Review the final diff for subtraction and scope**

Check:

```bash
git diff master...HEAD --stat
git diff master...HEAD -- lisp/p3-terminal.el lisp/p3-config-terminal.el lisp/p3-platform.el
git grep -nE 'vterm|ble\.sh|P3_BLESH_FILE' -- ':!docs/superpowers/*'
```

Expected: production terminal code is materially smaller/simpler than the previous vterm+ble.sh path; no unrelated project/workspace changes; no supported-code vterm/ble.sh references.

- [ ] **Step 6: Commit Windows CI coverage/final fixes**

```bash
git add .github/workflows/windows-platform-tests.yml test/p3-config-terminal-windows-test.el test/p3-terminal-test.el
git commit -m "test: cover project Bash workflow on Windows"
```

- [ ] **Step 7: Create the draft PR only after local/focused checks are green**

Use a draft PR referencing `#20`. Because the repository's CI policy runs substantive CI when a PR becomes ready for review, keep it draft through implementation/review and mark it ready only for the final CI gate.
