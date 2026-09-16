# Eshell + Eat Project Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the P3 project-shell backend with project-aware Eshell buffers and supported Eat terminal emulation, while preserving rich shell UX, native-Windows Rtools/MSYS2 tooling, and the existing P3 command surface.

**Architecture:** P3 continues to own semantic project identity and project-shell buffer lifecycle. Eshell becomes the persistent interactive shell surface; an idle project shell remains live because its managed Eshell buffer is live, not because a shell subprocess exists. Eat is enabled only through its supported global `eat-eshell-mode`, after an explicit Linux/native-Windows feasibility gate proves that its `stty` and `/usr/bin/env sh -c` process path works on both supported platforms.

**Tech Stack:** Emacs Lisp, built-in Eshell, Eat from NonGNU ELPA, `eshell-syntax-highlighting` from MELPA, Consult, ERT, GitHub Actions, Python 3 for the deterministic terminal fixture.

**Spec:** `docs/superpowers/specs/2026-09-16-eshell-eat-project-shell-design.md`

## Global Constraints

- The primary project-shell surface must work on GNU/Linux and native Windows; do not ship a Linux-only partial migration.
- The native-Windows Eat feasibility gate must pass before production project-shell code is migrated away from Comint/Bash.
- Use Eat's public `eat-eshell-mode`; do not depend on `eat--eshell-local-mode` or other private Eat helpers.
- Preserve `p3/project-shell`, `p3/project-shell-new`, switch, other-window, rename, kill, `C-x C-u`, and `C-c T` behavior.
- Preserve semantic project-root routing, including Org-associated projects.
- Preserve native-Windows Rtools/MSYS2 discovery and ordinary `M-x shell`; do not remove `p3/windows-configure-shell` as part of this migration.
- Do not add WSL, PowerShell, Git Bash, a multiplexer, or a second user-facing terminal workflow.
- Project-shell creation must not install packages or perform network work synchronously.
- Eat failure must leave ordinary Eshell usable and must not present repeated interactive fallback prompts.
- Keep CI economical: one explicit feasibility gate before migration, then one final Linux/native-Windows gate after implementation.

---

### Task 1: Prove Eat + Eshell on Linux and Native Windows Before Migration

**Files:**
- Create: `test/fixtures/p3-terminal-fixture.py`
- Create: `test/p3-eat-feasibility-test.el`
- Modify: `.github/workflows/emacs-tests.yml`
- Modify: `.github/workflows/windows-platform-tests.yml`

**Interfaces:**
- Consumes: current Rtools/MSYS2 PATH setup exposed through `P3_TEST_MSYS2_ROOT`; upstream public `eat-eshell-mode`.
- Produces: a permanent cross-platform terminal-contract fixture and a binary feasibility decision. Later tasks may proceed only if both CI platforms pass.

- [ ] **Step 1: Add a deterministic terminal fixture**

Create `test/fixtures/p3-terminal-fixture.py` with no third-party dependencies:

```python
#!/usr/bin/env python3
import os
import sys

exit_code = int(sys.argv[1]) if len(sys.argv) > 1 else 0

stdin_tty = int(sys.stdin.isatty())
stdout_tty = int(sys.stdout.isatty())
try:
    size = os.get_terminal_size(sys.stdout.fileno())
    columns, lines = size.columns, size.lines
except OSError:
    columns, lines = 0, 0

print(f"__P3_TTY__{stdin_tty}:{stdout_tty}", flush=True)
print(f"__P3_SIZE__{columns}:{lines}", flush=True)

# Exercise alternate-screen and cursor-addressing sequences while waiting for
# one raw input byte. Eat should render these rather than leave escape text in
# the Eshell buffer.
sys.stdout.write("\x1b[?1049h\x1b[2J\x1b[H__P3_TOP__")
sys.stdout.write("\x1b[2;5H__P3_CURSOR__")
sys.stdout.flush()

byte = sys.stdin.buffer.read(1)

sys.stdout.write("\x1b[?1049l")
sys.stdout.flush()
print(f"__P3_INPUT__{byte.hex()}", flush=True)
sys.exit(exit_code)
```

- [ ] **Step 2: Write the feasibility ERT test before changing production code**

Create `test/p3-eat-feasibility-test.el`. The test must load Eat as an external test dependency, create an ordinary Eshell buffer, enable the public global mode, execute the fixture in the foreground, use a timer to inspect/send input while Eshell is waiting, and assert the supported terminal contract:

```elisp
;;; p3-eat-feasibility-test.el --- Eat/Eshell platform gate -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'eshell)
(require 'esh-proc)
(require 'eat)

(defconst p3-eat-feasibility-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(defun p3-eat-feasibility-test--python ()
  (or (executable-find "python3")
      (executable-find "python")
      (ert-skip "Python is unavailable for Eat terminal fixture")))

(defun p3-eat-feasibility-test--run-fixture (exit-code)
  (let* ((name "*p3-eat-feasibility*")
         (eshell-buffer-name name)
         (fixture (expand-file-name "test/fixtures/p3-terminal-fixture.py"
                                    p3-eat-feasibility-test--root))
         (python (p3-eat-feasibility-test--python))
         (buffer (save-window-excursion (eshell)))
         observed-terminal
         observed-raw-escape
         input-sent)
    (unwind-protect
        (progn
          (eat-eshell-mode 1)
          (with-current-buffer buffer
            (run-at-time
             0.4 nil
             (lambda ()
               (when (buffer-live-p buffer)
                 (with-current-buffer buffer
                   (setq observed-terminal
                         (and (search-forward "__P3_CURSOR__" nil t) t)
                         observed-raw-escape
                         (save-excursion
                           (goto-char (point-min))
                           (search-forward "\e[" nil t)))
                   (when-let ((proc (eshell-head-process)))
                     (process-send-string proc "x")
                     (setq input-sent t))))))
            (goto-char (point-max))
            (insert (mapconcat #'shell-quote-argument
                               (list python fixture
                                     (number-to-string exit-code))
                               " "))
            (eshell-send-input)
            (should input-sent)
            (should observed-terminal)
            (should-not observed-raw-escape)
            (should (save-excursion
                      (goto-char (point-min))
                      (re-search-forward "__P3_TTY__1:1" nil t)))
            (should (save-excursion
                      (goto-char (point-min))
                      (re-search-forward "__P3_SIZE__[1-9][0-9]*:[1-9][0-9]*"
                                         nil t)))
            (should (save-excursion
                      (goto-char (point-min))
                      (re-search-forward "__P3_INPUT__78" nil t)))))
      (when (buffer-live-p buffer)
        (let ((kill-buffer-query-functions nil))
          (kill-buffer buffer))))))

(ert-deftest p3-eat-feasibility-supported-eshell-terminal-path ()
  (should (executable-find "stty"))
  (p3-eat-feasibility-test--run-fixture 0))
```

If the exact buffer-visible location of the alternate-screen marker differs under Eat, keep the behavioral assertions—interactive TTY, nonzero dimensions, raw input, no literal escape leakage, clean return—and adjust only the observation mechanism. Do not test or call private Eat functions.

- [ ] **Step 3: Run the feasibility test locally on GNU/Linux and confirm it is a real gate**

Install Eat into a disposable batch package directory, initialize packages, and run only the gate:

```bash
rm -rf /tmp/p3-eat-elpa
emacs -Q --batch \
  --eval '(require (quote package))' \
  --eval '(setq package-user-dir "/tmp/p3-eat-elpa")' \
  --eval '(setq package-archives (quote (("nongnu" . "https://elpa.nongnu.org/nongnu/"))))' \
  --eval '(package-initialize)' \
  --eval '(package-refresh-contents)' \
  --eval '(package-install (quote eat))'

emacs -Q --batch -L lisp \
  --eval '(require (quote package))' \
  --eval '(setq package-user-dir "/tmp/p3-eat-elpa")' \
  --eval '(package-initialize)' \
  -l test/p3-eat-feasibility-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS. A failure here is a backend-feasibility failure, not a reason to change P3 production code.

- [ ] **Step 4: Add one package-install + feasibility step to each CI workflow**

In both workflows, install Eat from NonGNU ELPA into the runner's normal package directory, then run `test/p3-eat-feasibility-test.el` with `package-initialize`. On Windows, extend the existing MSYS2 root validation so it also requires `usr/bin/stty.exe`, `usr/bin/env.exe`, and `usr/bin/sh.exe` before the ERT test runs.

Linux workflow command shape:

```yaml
- name: Install Eat feasibility dependency
  run: |
    emacs -Q --batch \
      --eval '(require (quote package))' \
      --eval '(setq package-archives (quote (("nongnu" . "https://elpa.nongnu.org/nongnu/"))))' \
      --eval '(package-refresh-contents)' \
      --eval '(package-install (quote eat))'

- name: Run Eat Eshell feasibility gate
  run: |
    emacs -Q --batch -L lisp \
      --eval '(require (quote package))' \
      --eval '(package-initialize)' \
      -l test/p3-eat-feasibility-test.el \
      -f ert-run-tests-batch-and-exit
```

Windows uses the same Lisp forms in PowerShell's folded command syntax.

- [ ] **Step 5: Commit the isolated spike**

```bash
git add test/fixtures/p3-terminal-fixture.py \
        test/p3-eat-feasibility-test.el \
        .github/workflows/emacs-tests.yml \
        .github/workflows/windows-platform-tests.yml
git commit -m "test: gate Eat Eshell terminal support"
```

- [ ] **Step 6: Trigger exactly one Linux/native-Windows feasibility CI pass**

Open the implementation PR as draft, then mark it ready once to trigger the repository's `opened`/`ready_for_review` CI policy. Inspect both jobs.

**STOP CONDITION:** If native Windows fails because Eat cannot execute its supported process wrapper, establish a TTY, or render/restore the fixture, stop this plan. Keep the current Comint/Bash production backend unchanged and return to the design stage to select another terminal-emulation backend. Do not continue to Task 2.

---

### Task 2: Redefine Project-Shell Lifecycle Around Managed Eshell Buffers

**Files:**
- Modify: `test/p3-terminal-test.el`
- Modify: `test/p3-terminal-integration-test.el`
- Modify: `lisp/p3-terminal.el`

**Interfaces:**
- Consumes: `p3/project-shell-root`, `p3/project-normalize-root`, `eshell-buffer-name`, public `eshell`.
- Produces: `p3/project-shell-buffer-p`, `p3/project-shell-live-p`, and `p3/project-shell--start` with buffer-backed Eshell semantics; existing public P3 shell commands remain unchanged.

- [ ] **Step 1: Replace the process-liveness test with a managed-Eshell-buffer test**

Replace `p3-terminal-project-shell-live-p-requires-live-process` with tests equivalent to:

```elisp
(ert-deftest p3-terminal-project-shell-live-p-is-buffer-backed ()
  (let ((buffer (generate-new-buffer " *p3-eshell-live-test*")))
    (unwind-protect
        (with-current-buffer buffer
          (eshell-mode)
          (setq-local p3/project-shell-root-value temporary-file-directory)
          (should (p3/project-shell-live-p buffer))
          (should-not (get-buffer-process buffer)))
      (kill-buffer buffer))))

(ert-deftest p3-terminal-project-shell-live-p-rejects-non-eshell-buffer ()
  (let ((buffer (generate-new-buffer " *p3-not-eshell*")))
    (unwind-protect
        (with-current-buffer buffer
          (setq-local p3/project-shell-root-value temporary-file-directory)
          (should-not (p3/project-shell-live-p buffer)))
      (kill-buffer buffer))))
```

Delete or rewrite `p3-terminal-dead-process-primary-is-restarted`; child-process exit must no longer invalidate the session.

- [ ] **Step 2: Run the lifecycle tests and verify RED**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-terminal-test.el \
  --eval '(ert-run-tests-batch-and-exit "p3-terminal-project-shell-live-p")'
```

Expected: FAIL because current `p3/project-shell-live-p` requires `get-buffer-process`.

- [ ] **Step 3: Implement Eshell-backed liveness and startup minimally**

In `lisp/p3-terminal.el`:

```elisp
(require 'eshell)

(defun p3/project-shell-buffer-p (buffer)
  "Return non-nil when BUFFER is a managed P3 project Eshell."
  (and (buffer-live-p buffer)
       (buffer-local-value 'p3/project-shell-root-value buffer)
       (with-current-buffer buffer
         (derived-mode-p 'eshell-mode))))

(defun p3/project-shell-live-p (buffer)
  "Return non-nil when BUFFER is a live managed P3 project Eshell."
  (p3/project-shell-buffer-p buffer))

(defun p3/project-shell--start (name root)
  "Start a managed Eshell named NAME at ROOT and return its buffer."
  (let ((default-directory root)
        (eshell-buffer-name name))
    (let ((buffer (save-window-excursion (eshell))))
      (with-current-buffer buffer
        (setq-local p3/project-shell-root-value root)
        (p3/project-shell-mode-setup))
      buffer)))
```

Do not remove the old Bash/Comint constants yet; cleanup waits until the complete Eshell path and both platform gates pass.

- [ ] **Step 4: Make the primary registry forget killed buffers**

Add a buffer-local cleanup hook:

```elisp
(defun p3/project-shell--forget-primary ()
  "Forget the current buffer if it owns its project's primary mapping."
  (when-let ((root p3/project-shell-root-value))
    (when (eq (gethash root p3/project-shell-buffers) (current-buffer))
      (remhash root p3/project-shell-buffers))))
```

Add it from `p3/project-shell-mode-setup` with:

```elisp
(add-hook 'kill-buffer-hook #'p3/project-shell--forget-primary nil t)
```

- [ ] **Step 5: Add an idle-buffer reuse regression**

```elisp
(ert-deftest p3-terminal-idle-eshell-primary-is-reused ()
  (let ((p3/project-shell-buffers (make-hash-table :test #'equal))
        (root (file-name-as-directory temporary-file-directory)))
    (cl-letf (((symbol-function 'p3/project-shell-root) (lambda () root)))
      (let ((first (p3/project-shell-buffer)))
        (unwind-protect
            (progn
              (should-not (get-buffer-process first))
              (should (eq first (p3/project-shell-buffer))))
          (kill-buffer first))))))
```

- [ ] **Step 6: Run the focused lifecycle suite**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-terminal-test.el \
  --eval '(ert-run-tests-batch-and-exit "p3-terminal-\\(project-shell-live-p\\|idle-eshell-primary\\|primary-shell\\|extra-session\\|stale-primary\\)")'
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lisp/p3-terminal.el test/p3-terminal-test.el test/p3-terminal-integration-test.el
git commit -m "refactor: back project shells with Eshell buffers"
```

---

### Task 3: Preserve Project Routing and Session Commands Under Eshell

**Files:**
- Modify: `test/p3-project-context-test.el`
- Modify: `test/p3-terminal-integration-test.el`
- Modify: `lisp/p3-terminal.el`

**Interfaces:**
- Consumes: Task 2 managed-buffer lifecycle.
- Produces: unchanged public P3 command surface with Eshell-backed primary/extra buffers.

- [ ] **Step 1: Convert Bash-process integration assertions to Eshell buffer assertions**

Replace `p3-terminal-real-bash-process-starts-at-project-root` with a real Eshell startup test:

```elisp
(ert-deftest p3-terminal-real-eshell-starts-at-project-root ()
  (let* ((raw-root (make-temp-file "p3-real-eshell-" t))
         (root (p3/project-normalize-root raw-root))
         (p3/project-shell-buffers (make-hash-table :test #'equal))
         buffer)
    (unwind-protect
        (cl-letf (((symbol-function 'p3/project-root)
                   (lambda (&optional _error-on-unavailable) raw-root)))
          (setq buffer (p3/project-shell-buffer))
          (with-current-buffer buffer
            (should (derived-mode-p 'eshell-mode))
            (should (equal (p3/project-normalize-root default-directory) root))
            (should (equal p3/project-shell-root-value root))))
      (when (buffer-live-p buffer) (kill-buffer buffer))
      (delete-directory raw-root t))))
```

Remove project-shell tests for `shell--start-prog`, Bash history-ring file names, `CHERE_INVOKING`, and `shell-resync-dirs`; those remain covered by the generic Windows `M-x shell` tests where applicable.

- [ ] **Step 2: Strengthen the Org-associated project regression**

Keep `p3-project-shell-uses-associated-org-project-root`, but assert the returned buffer is `eshell-mode`, its stored `p3/project-shell-root-value` equals the associated root, and its `default-directory` starts there.

- [ ] **Step 3: Verify extra/switch/rename/kill/toggle behavior still depends only on managed buffers**

Add or adapt tests so:

```elisp
(should (eq primary (p3/project-shell-buffer)))
(should-not (eq primary (p3/project-shell-buffer t)))
(should (memq primary (p3/project-shell-buffers)))
```

and killing the primary makes the next lookup create a new Eshell buffer while killing an extra session does not affect the primary mapping.

- [ ] **Step 4: Run routing and session tests**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-project-context-test.el \
  -l test/p3-terminal-test.el \
  --eval '(ert-run-tests-batch-and-exit "p3-\\(project-shell\\|terminal-\\(extra\\|primary\\|stale\\|real-eshell\\|command-map\\)\\)")'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lisp/p3-terminal.el test/p3-project-context-test.el test/p3-terminal-integration-test.el test/p3-terminal-test.el
git commit -m "test: preserve project shell routing under Eshell"
```

---

### Task 4: Restore Prompt, History, Completion, and Rich Input UX Natively in Eshell

**Files:**
- Modify: `lisp/p3-terminal.el`
- Modify: `lisp/p3-config-terminal.el`
- Modify: `test/p3-terminal-rich-ux-test.el`
- Modify: `test/p3-config-terminal-test.el`

**Interfaces:**
- Consumes: managed Eshell buffers from Task 2; existing Consult completion configuration.
- Produces: `p3/project-shell-prompt`, `p3/project-shell-mode-setup`, Emacs-29 append-history compatibility helper, `C-r -> consult-history`, global `eshell-syntax-highlighting` package activation.

- [ ] **Step 1: Write RED tests for Eshell-native rich UX**

Replace Bash/Starship/Comint assertions with tests for:

```elisp
(ert-deftest p3-terminal-eshell-setup-uses-native-history-search ()
  (with-temp-buffer
    (eshell-mode)
    (setq-local p3/project-shell-root-value temporary-file-directory)
    (p3/project-shell-mode-setup)
    (should eshell-hist-ignoredups)
    (should (eq (key-binding (kbd "C-r")) #'consult-history))))

(ert-deftest p3-terminal-prompt-shows-directory-and-status-marker ()
  (let ((default-directory temporary-file-directory)
        (eshell-last-command-status 0))
    (should (string-match-p "❯ " (p3/project-shell-prompt))))
  (let ((default-directory temporary-file-directory)
        (eshell-last-command-status 1))
    (should (string-match-p "❯ " (p3/project-shell-prompt)))))
```

In `p3-config-terminal-test.el`, assert the config owns `use-package eat` and `use-package eshell-syntax-highlighting` and still contains no `vterm` package declaration.

- [ ] **Step 2: Run the rich-UX tests and verify RED**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-terminal-rich-ux-test.el \
  -l test/p3-config-terminal-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: FAIL on the new Eshell prompt/history/package expectations.

- [ ] **Step 3: Implement a cheap Eshell-native P3 prompt**

Add:

```elisp
(defconst p3/project-shell-prompt-regexp "^[^❯\n]*❯ "
  "Prompt regexp for P3 Eshell buffers on Emacs versions that need it.")

(defun p3/project-shell-prompt ()
  "Return the prompt for the current P3 project Eshell."
  (let* ((root p3/project-shell-root-value)
         (directory (file-name-as-directory (expand-file-name default-directory)))
         (relative (and root (file-in-directory-p directory root)
                        (file-relative-name directory root)))
         (label (if relative
                    (concat (file-name-nondirectory (directory-file-name root))
                            (unless (equal relative "./")
                              (concat "/" (directory-file-name relative))))
                  (abbreviate-file-name directory)))
         (ok (or (not (boundp 'eshell-last-command-status))
                 (zerop eshell-last-command-status))))
    (concat (propertize label 'face 'eshell-prompt)
            " "
            (propertize "❯" 'face (if ok 'success 'error))
            " ")))
```

Do not shell out for Git/Starship on every prompt. Additional prompt data is outside this migration unless profiling later shows it is cheap.

- [ ] **Step 4: Implement cross-version persistent history without clobbering concurrent sessions**

Emacs 30 has `eshell-history-append`; Emacs 29 has the `APPEND` argument on `eshell-write-history` but no user option. Add a compatibility helper:

```elisp
(defun p3/project-shell--append-history-compat ()
  "Append new Eshell history on versions without `eshell-history-append'."
  (when (and (not (boundp 'eshell-history-append))
             (bound-and-true-p eshell-history-ring))
    (eshell-write-history eshell-history-file-name t)))
```

In `p3/project-shell-mode-setup`:

```elisp
(setq-local eshell-prompt-function #'p3/project-shell-prompt
            eshell-prompt-regexp p3/project-shell-prompt-regexp
            eshell-hist-ignoredups t)
(local-set-key (kbd "C-r") #'consult-history)
(if (boundp 'eshell-history-append)
    (setq-local eshell-history-append t)
  (setq-local eshell-save-history-on-exit nil)
  (add-hook 'eshell-pre-command-hook
            #'p3/project-shell--append-history-compat nil t))
```

Require/declare only the built-in Eshell history functions needed for byte compilation; do not duplicate Eshell's history implementation.

- [ ] **Step 5: Configure syntax highlighting through one maintained package**

Update `lisp/p3-config-terminal.el`:

```elisp
(require 'use-package)

(use-package eshell-syntax-highlighting
  :after esh-mode
  :config
  (eshell-syntax-highlighting-global-mode 1))
```

The repository already has MELPA configured and `use-package-always-ensure t`, so no custom installer belongs in project-shell startup.

- [ ] **Step 6: Add history regressions for both Emacs generations**

On Emacs 30+, assert `eshell-history-append` becomes buffer-local and non-nil. On Emacs 29, create two Eshell buffers sharing a temporary `eshell-history-file-name`, add distinct commands to each history ring, invoke the P3 append helper, and assert the file contains both commands without P3 bootstrap text.

- [ ] **Step 7: Run rich UX tests**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-terminal-rich-ux-test.el \
  -l test/p3-terminal-test.el \
  -l test/p3-config-terminal-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS for all Eshell-native rich-UX tests.

- [ ] **Step 8: Commit**

```bash
git add lisp/p3-terminal.el lisp/p3-config-terminal.el \
        test/p3-terminal-rich-ux-test.el test/p3-config-terminal-test.el
git commit -m "feat: restore rich project Eshell UX"
```

---

### Task 5: Enable Supported Eat Integration with Deterministic Fallback

**Files:**
- Modify: `lisp/p3-config-terminal.el`
- Modify: `test/p3-config-terminal-test.el`
- Modify: `test/p3-terminal-integration-test.el`

**Interfaces:**
- Consumes: Task 1 proven upstream `eat-eshell-mode` path; Task 2 Eshell shell buffers.
- Produces: globally enabled public Eat Eshell integration with `eat-eshell-fallback-if-stty-not-available = t` and no private Eat calls.

- [ ] **Step 1: Add config tests that reject private Eat integration**

Assert the parsed/config text contains `eat-eshell-mode` and deterministic fallback, and does not contain `eat--eshell-local-mode`:

```elisp
(ert-deftest p3-config-terminal-uses-supported-eat-eshell-integration ()
  (let ((contents (p3-config-terminal-test--contents "lisp/p3-config-terminal.el")))
    (should (string-match-p "eat-eshell-mode" contents))
    (should (string-match-p "eat-eshell-fallback-if-stty-not-available" contents))
    (should-not (string-match-p "eat--eshell-local-mode" contents))))
```

- [ ] **Step 2: Verify RED**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-terminal-test.el \
  --eval '(ert-run-tests-batch-and-exit "p3-config-terminal-uses-supported-eat")'
```

Expected: FAIL.

- [ ] **Step 3: Configure Eat in the package-owning module**

Add:

```elisp
(use-package eat
  :after eshell
  :custom
  (eat-eshell-fallback-if-stty-not-available t)
  :config
  (eat-eshell-mode 1))
```

This intentionally accepts Eat's global Eshell integration. P3 project-shell code must not `require` Eat or call its private local mode.

- [ ] **Step 4: Add a deterministic no-`stty` fallback regression**

The test should temporarily make `eshell-search-path` return nil for `stty`, set `eat-eshell-fallback-if-stty-not-available` to `t`, and verify an external command follows plain Eshell behavior without invoking `y-or-n-p`. Stub `y-or-n-p` to `ert-fail` so an accidental interactive prompt is caught.

- [ ] **Step 5: Run the config and integration tests with Eat installed**

```bash
emacs -Q --batch -L lisp \
  --eval '(require (quote package))' \
  --eval '(package-initialize)' \
  -l test/p3-config-terminal-test.el \
  -l test/p3-terminal-integration-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lisp/p3-config-terminal.el test/p3-config-terminal-test.el test/p3-terminal-integration-test.el
git commit -m "feat: add Eat terminal emulation to project Eshell"
```

---

### Task 6: Turn the Feasibility Fixture into the Permanent P3 Terminal Contract

**Files:**
- Modify: `test/p3-eat-feasibility-test.el`
- Modify: `test/p3-terminal-integration-test.el`
- Modify: `.github/workflows/emacs-tests.yml`
- Modify: `.github/workflows/windows-platform-tests.yml`

**Interfaces:**
- Consumes: production P3 Eshell backend plus Eat configuration.
- Produces: permanent behavioral regression coverage for terminalization and clean return to the same managed project shell.

- [ ] **Step 1: Add a P3-level foreground fixture test**

Use `p3/project-shell-buffer` rather than a raw Eshell buffer. While the fixture is running, assert terminal output is interpreted, raw input reaches the child, and after it exits:

```elisp
(should (p3/project-shell-live-p buffer))
(should (eq buffer (p3/project-shell-buffer)))
(with-current-buffer buffer
  (should (derived-mode-p 'eshell-mode))
  (should-not (eshell-head-process)))
```

Run the fixture once with exit code `0` and once with a nonzero exit code such as `7`; both must return to the same P3 shell buffer.

- [ ] **Step 2: Add resize/dimension coverage**

Create the shell in a selected window with a known practical size, run the fixture, and assert reported rows and columns are positive. Resize the window before a second run and assert at least one reported dimension changes. Avoid asserting exact frame-specific numbers.

- [ ] **Step 3: Run the terminal-contract tests locally**

```bash
emacs -Q --batch -L lisp \
  --eval '(require (quote package))' \
  --eval '(package-initialize)' \
  -l test/p3-eat-feasibility-test.el \
  -l test/p3-terminal-test.el \
  --eval '(ert-run-tests-batch-and-exit "p3-.*terminal.*\\|p3-eat-feasibility")'
```

Expected: PASS.

- [ ] **Step 4: Keep the workflow gate focused**

The regular Linux and Windows test jobs should install Eat once and load both `test/p3-eat-feasibility-test.el` and the P3 terminal tests. Do not add a second package installation or another workflow solely for the same contract.

- [ ] **Step 5: Commit**

```bash
git add test/p3-eat-feasibility-test.el test/p3-terminal-integration-test.el \
        .github/workflows/emacs-tests.yml .github/workflows/windows-platform-tests.yml
git commit -m "test: cover project Eshell terminal contract"
```

---

### Task 7: Remove Displaced Project-Shell Comint/Bash/Starship Machinery Only After Both Platforms Work

**Files:**
- Modify: `lisp/p3-terminal.el`
- Modify: `test/p3-terminal-test.el`
- Modify: `test/p3-terminal-integration-test.el`
- Modify: `test/p3-terminal-rich-ux-test.el`
- Delete if unused: `templates/p3-starship.toml`
- Preserve: `lisp/p3-platform.el`
- Preserve/update tests: `test/p3-config-terminal-windows-test.el`, `test/p3-platform-test.el`

**Interfaces:**
- Consumes: green Eshell lifecycle, rich UX, and Eat terminal contract on both platforms.
- Produces: one project-shell implementation with no dead Comint/Bash compatibility layer.

- [ ] **Step 1: Search repository consumers before deletion**

Run:

```bash
git grep -nE 'project-shell-prompt-init-command|project-shell-rich-terminfo|project-shell-comint-terminal|p3-starship|STARSHIP_CONFIG|shell-dirstack-query|CHERE_INVOKING'
```

Classify each match as project-shell-specific or generic `M-x shell`/platform behavior. Do not remove generic Windows shell support.

- [ ] **Step 2: Write/retain tests protecting ordinary Windows `M-x shell`**

`test/p3-config-terminal-windows-test.el` must continue to assert that `p3/windows-configure-shell` chooses the Rtools/MSYS2 shell and installs CRLF/UTF-8 safeguards. If existing coverage already proves this, retain it unchanged rather than duplicating it.

- [ ] **Step 3: Remove only obsolete project-shell code**

Delete from `p3-terminal.el` after confirming no consumer remains:

```text
p3/project-shell-prompt-pattern         ; old Comint pattern
p3/project-shell-prompt-init-command    ; injected Bash bootstrap
p3/project-shell-starship-config
p3/project-shell-rich-terminfo-p
p3/project-shell-comint-terminal
explicit-bash.exe-args project-shell bindings
shell-fontify-input-enable project-shell binding
shell-highlight-undef-enable project-shell binding
shell-prompt-pattern project-shell binding
STARSHIP_CONFIG project-shell environment mutation
HISTFILE project-shell environment mutation
CHERE_INVOKING project-shell environment mutation
shell-eval-command project-shell bootstrap
shell-dirstack-query project-shell setup
```

Keep `p3/windows-configure-shell`, its `shell-mode-hook`, and its platform discovery in `p3-platform.el`.

- [ ] **Step 4: Delete the tracked Starship file only if the repository search is clean**

```bash
git grep -n 'p3-starship.toml' -- ':!docs/superpowers/**'
```

Expected: no supported runtime/test consumer. Then:

```bash
git rm templates/p3-starship.toml
```

- [ ] **Step 5: Remove old implementation-specific Bash tests**

Delete/replace tests whose only contract was:

```text
Bash --noediting -i
Comint input fontification variables
Starship initialization/fallback
rich Comint terminfo
Bash HISTFILE/histappend
project-shell shell-resync-dirs
project-shell CHERE_INVOKING
```

Do not delete equivalent generic Windows shell tests.

- [ ] **Step 6: Run focused cleanup regressions**

```bash
emacs -Q --batch -L lisp \
  --eval '(require (quote package))' \
  --eval '(package-initialize)' \
  -l test/p3-platform-test.el \
  -l test/p3-config-terminal-windows-test.el \
  -l test/p3-terminal-test.el \
  -l test/p3-config-terminal-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS; ordinary Windows shell coverage remains intact.

- [ ] **Step 7: Commit**

```bash
git add lisp/p3-terminal.el test/p3-terminal-test.el \
        test/p3-terminal-integration-test.el test/p3-terminal-rich-ux-test.el \
        test/p3-config-terminal-windows-test.el test/p3-platform-test.el
git add -u templates/p3-starship.toml
git commit -m "refactor: retire project Bash shell machinery"
```

---

### Task 8: Final Architecture, CI, and Manual Acceptance Verification

**Files:**
- Modify as needed: `.github/workflows/emacs-tests.yml`
- Modify as needed: `.github/workflows/windows-platform-tests.yml`
- Modify: `test/p3-config-terminal-test.el`
- Modify: `test/p3-integration-cleanup-test.el` if it tracks retired artifacts
- Modify: documentation/roadmap only if current shell architecture is described there

**Interfaces:**
- Consumes: all previous tasks.
- Produces: merge-ready cross-platform project-shell implementation and final evidence.

- [ ] **Step 1: Add architecture assertions that prevent regression to multiple shell stacks**

Keep `p3-config-terminal-uses-one-project-shell-surface`, and extend it so P3 terminal configuration contains one Eshell project-shell path, owns Eat and syntax highlighting at the config boundary, contains no vterm declaration, and contains no project-shell call to `shell`/`shell-mode`.

- [ ] **Step 2: Run strict byte compilation**

Use the same strict compiler boundary as CI, including:

```bash
emacs -Q --batch -L lisp \
  --eval '(require (quote use-package-ensure))' \
  --eval '(setq use-package-ensure-function (lambda (&rest _) t))' \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile lisp/p3-terminal.el lisp/p3-config-terminal.el
```

Expected: no warnings/errors.

- [ ] **Step 3: Run the full Linux ERT suite**

Run the exact `Run ERT test suite` command from `.github/workflows/emacs-tests.yml`, with installed Eat available through `package-initialize` where the terminal tests need it.

Expected: zero unexpected failures.

- [ ] **Step 4: Run a Linux manual Codex smoke**

From a real project buffer:

```text
C-x C-u
codex
```

Verify: one initial Eshell prompt; Codex renders as a usable TUI; normal keyboard interaction works; resizing does not corrupt the UI; exiting Codex returns to the same Eshell buffer; `C-x C-u` still toggles back to the previous buffer; invoking `C-x C-u` again reuses the same project shell.

- [ ] **Step 5: Run a native-Windows manual Codex smoke**

Repeat the same sequence in native Windows Emacs using the normal Rtools/MSYS2 environment. Also verify an ordinary Unix-oriented external command such as `git --version` and an explicit `bash -lc 'pwd'` resolve from the configured environment.

This manual smoke is required before merge even though CI uses the deterministic fixture.

- [ ] **Step 6: Re-run repository cleanup searches**

```bash
git grep -nE 'vterm|ble\.sh|project-shell-prompt-init-command|p3-starship|STARSHIP_CONFIG' -- ':!docs/superpowers/**' || true
git grep -n 'p3/project-shell' lisp test
```

Review every remaining hit. Runtime hits for retired project-shell machinery are failures; historical documentation references are acceptable if clearly historical.

- [ ] **Step 7: Commit final test/documentation adjustments**

```bash
git add .github/workflows test lisp docs
git commit -m "test: finalize Eshell project shell migration"
```

- [ ] **Step 8: Trigger the final Linux/native-Windows CI gate once**

If the PR was returned to draft after the feasibility spike, mark it ready now. Verify:

```text
Linux byte compilation: PASS
Linux full ERT suite: PASS
Linux Eat/Eshell terminal contract: PASS
Windows boundary compilation: PASS
Windows platform/config ERT: PASS
Windows Eat/Eshell terminal contract: PASS
```

Do not claim the migration complete until both workflow runs are green and the two manual Codex smokes have passed.
