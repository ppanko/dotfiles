# Eshell + Eat Project Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the P3 project-shell backend with project-aware Eshell buffers and supported Eat terminal emulation, while preserving rich shell UX, native-Windows Rtools/MSYS2 tooling, and the existing P3 command surface.

**Architecture:** P3 continues to own semantic project identity and project-shell buffer lifecycle. Eshell becomes the persistent interactive shell surface; an idle project shell remains live because its managed Eshell buffer is live, not because a shell subprocess exists. Eat is enabled only through its supported global `eat-eshell-mode`, after a Linux/native-Windows feasibility gate proves that its `stty` and `/usr/bin/env sh -c` process path works on both supported platforms.

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
- Keep startup lazy: `p3-terminal.el` must not eagerly load Eshell or Eat during configuration startup.
- Keep CI economical: one explicit feasibility run before migration, then one final Linux/native-Windows run after implementation.

---

### Task 1: Prove Eat + Eshell on Linux and Native Windows Before Migration

**Files:**
- Create: `test/fixtures/p3-terminal-fixture.py`
- Create: `test/p3-eat-feasibility-test.el`
- Modify: `.github/workflows/emacs-tests.yml`
- Modify: `.github/workflows/windows-platform-tests.yml`

**Interfaces:**
- Consumes: the existing Windows MSYS2 test environment exposed through `P3_TEST_MSYS2_ROOT`; upstream public `eat-eshell-mode`.
- Produces: a permanent cross-platform terminal fixture and a binary feasibility decision. Tasks 2-8 are blocked until both platform gates pass.

- [ ] **Step 1: Add a deterministic terminal fixture**

Create `test/fixtures/p3-terminal-fixture.py`:

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

# Enter alternate screen, clear it, and use cursor addressing. The test inspects
# the live Eat-rendered region before sending the byte that lets this process exit.
sys.stdout.write("\x1b[?1049h\x1b[2J\x1b[H__P3_TOP__")
sys.stdout.write("\x1b[2;5H__P3_CURSOR__")
sys.stdout.flush()

byte = sys.stdin.buffer.read(1)

sys.stdout.write("\x1b[?1049l")
sys.stdout.flush()
print(f"__P3_INPUT__{byte.hex()}", flush=True)
sys.exit(exit_code)
```

- [ ] **Step 2: Write the feasibility ERT test without touching production shell code**

Create `test/p3-eat-feasibility-test.el`:

```elisp
;;; p3-eat-feasibility-test.el --- Eat/Eshell platform gate -*- lexical-binding: t; -*-

(require 'ert)
(require 'eshell)
(require 'esh-proc)
(require 'eat)
(require 'p3-platform)

(defconst p3-eat-feasibility-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(defun p3-eat-feasibility-test--python ()
  (or (executable-find "python3")
      (executable-find "python")
      (ert-skip "Python is unavailable for Eat terminal fixture")))

(defun p3-eat-feasibility-test--prepare-platform ()
  (when (eq system-type 'windows-nt)
    (let* ((msys-root
            (or (getenv "P3_TEST_MSYS2_ROOT")
                (ert-skip "P3_TEST_MSYS2_ROOT is required on Windows")))
           (usr-bin (file-name-as-directory
                     (expand-file-name "usr/bin" msys-root))))
      (setq linuxy-environment-path usr-bin)
      (p3/windows-path-prepend usr-bin))))

(defun p3-eat-feasibility-test--run-fixture (exit-code)
  (p3-eat-feasibility-test--prepare-platform)
  (let* ((name "*p3-eat-feasibility*")
         (eshell-buffer-name name)
         (fixture (expand-file-name "test/fixtures/p3-terminal-fixture.py"
                                    p3-eat-feasibility-test--root))
         (python (p3-eat-feasibility-test--python))
         (eat-eshell-fallback-if-stty-not-available t)
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
                   (save-excursion
                     (goto-char (point-min))
                     (setq observed-terminal
                           (and (search-forward "__P3_CURSOR__" nil t) t))
                     (goto-char (point-min))
                     (setq observed-raw-escape
                           (search-forward "\033[" nil t)))
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
                      (re-search-forward
                       "__P3_SIZE__[1-9][0-9]*:[1-9][0-9]*" nil t)))
            (should (save-excursion
                      (goto-char (point-min))
                      (re-search-forward "__P3_INPUT__78" nil t)))))
      (when (buffer-live-p buffer)
        (let ((kill-buffer-query-functions nil))
          (kill-buffer buffer))))))

(ert-deftest p3-eat-feasibility-supported-eshell-terminal-path ()
  (p3-eat-feasibility-test--prepare-platform)
  (should (executable-find "stty"))
  (should (executable-find "env"))
  (should (executable-find "sh"))
  (p3-eat-feasibility-test--run-fixture 0))
```

This deliberately exercises Eat's supported integration rather than reproducing its private process setup.

- [ ] **Step 3: Run the gate locally on GNU/Linux**

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

Expected: PASS.

- [ ] **Step 4: Add exact Linux CI steps for the gate**

Append before the regular ERT suite in `.github/workflows/emacs-tests.yml`:

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

Add these paths to the workflow trigger list if the Linux workflow later switches from `paths-ignore` to explicit paths; under the current `paths-ignore` policy the new test/workflow changes already trigger it.

- [ ] **Step 5: Strengthen Windows MSYS validation and add exact Windows gate steps**

In the existing `Locate Git for Windows MSYS2 root` PowerShell block, add:

```powershell
foreach ($tool in @("stty.exe", "env.exe", "sh.exe")) {
  if (-not (Test-Path (Join-Path $gitRoot "usr/bin/$tool"))) {
    throw "Git for Windows MSYS2 $tool not found under $gitRoot"
  }
}
```

Then add:

```yaml
      - name: Install Eat feasibility dependency
        shell: powershell
        run: >-
          emacs -Q --batch
          --eval '(require (quote package))'
          --eval '(setq package-archives (quote (("nongnu" . "https://elpa.nongnu.org/nongnu/"))))'
          --eval '(package-refresh-contents)'
          --eval '(package-install (quote eat))'

      - name: Run Eat Eshell feasibility gate
        shell: powershell
        run: >-
          emacs -Q --batch -L lisp
          --eval '(require (quote package))'
          --eval '(package-initialize)'
          -l test/p3-eat-feasibility-test.el
          -f ert-run-tests-batch-and-exit
```

Add `test/p3-eat-feasibility-test.el` and `test/fixtures/p3-terminal-fixture.py` to the Windows workflow `paths` trigger.

- [ ] **Step 6: Commit only the feasibility spike**

```bash
git add test/fixtures/p3-terminal-fixture.py \
        test/p3-eat-feasibility-test.el \
        .github/workflows/emacs-tests.yml \
        .github/workflows/windows-platform-tests.yml
git commit -m "test: gate Eat Eshell terminal support"
```

- [ ] **Step 7: Trigger one cross-platform feasibility run and enforce the stop gate**

Open the implementation PR as draft, then mark it ready once. Inspect both workflow results.

**STOP CONDITION:** If native Windows cannot execute Eat's supported process wrapper, establish an interactive TTY, render the fixture, or return cleanly to Eshell, stop this plan. Leave production `p3-terminal.el` on the current Comint/Bash backend and return to the design stage to choose another terminal-emulation backend. Do not continue to Task 2.

After both feasibility jobs pass, convert the PR back to draft so subsequent implementation commits do not consume another full CI run until Task 8.

---

### Task 2: Redefine Project-Shell Lifecycle Around Managed Eshell Buffers

**Files:**
- Modify: `test/p3-terminal-test.el`
- Modify: `test/p3-terminal-integration-test.el`
- Modify: `lisp/p3-terminal.el`

**Interfaces:**
- Consumes: `p3/project-shell-root`, `p3/project-normalize-root`, dynamically bound `eshell-buffer-name`, public `eshell`.
- Produces: buffer-backed `p3/project-shell-buffer-p`, `p3/project-shell-live-p`, and `p3/project-shell--start`; public P3 shell commands remain unchanged.

- [ ] **Step 1: Write RED managed-buffer lifecycle tests**

Replace `p3-terminal-project-shell-live-p-requires-live-process` and the dead-process restart expectation with:

```elisp
(require 'eshell)

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

(ert-deftest p3-terminal-idle-primary-remains-reusable ()
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

- [ ] **Step 2: Run the new lifecycle selector and confirm RED**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-terminal-test.el \
  --eval '(ert-run-tests-batch-and-exit "p3-terminal-\\(project-shell-live-p\\|idle-primary\\)")'
```

Expected: FAIL because the current implementation requires a live shell process.

- [ ] **Step 3: Implement lazy Eshell startup and buffer-backed liveness**

Do not add a top-level `(require 'eshell)`. Add declarations near the top of `p3-terminal.el`:

```elisp
(defvar eshell-buffer-name)
(declare-function eshell "eshell" (&optional arg))
```

Replace the buffer/liveness functions and startup path with:

```elisp
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
  (require 'eshell)
  (let ((default-directory root)
        (eshell-buffer-name name))
    (let ((buffer (save-window-excursion (eshell))))
      (with-current-buffer buffer
        (setq-local p3/project-shell-root-value root)
        (p3/project-shell-mode-setup))
      buffer)))
```

Leave old Comint/Bash helper definitions in place temporarily; Task 7 removes them after the complete path is verified.

- [ ] **Step 4: Clear primary mappings when their buffer is killed**

Add:

```elisp
(defun p3/project-shell--forget-primary ()
  "Forget the current buffer if it owns its project's primary mapping."
  (when-let ((root p3/project-shell-root-value))
    (when (eq (gethash root p3/project-shell-buffers) (current-buffer))
      (remhash root p3/project-shell-buffers))))
```

and add this buffer-locally from `p3/project-shell-mode-setup`:

```elisp
(add-hook 'kill-buffer-hook #'p3/project-shell--forget-primary nil t)
```

- [ ] **Step 5: Add killed-primary and child-process-exit regressions**

Assert that killing the primary causes replacement on the next lookup, while running and then exiting any external command does not replace the Eshell buffer:

```elisp
(should (eq first (p3/project-shell-buffer)))
(kill-buffer first)
(should-not (eq first (p3/project-shell-buffer)))
```

For child-process independence, execute a short external command in the real Eshell and assert the original buffer is still returned after the process exits.

- [ ] **Step 6: Run the focused lifecycle tests**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-terminal-test.el \
  --eval '(ert-run-tests-batch-and-exit "p3-terminal-\\(project-shell-live-p\\|idle-primary\\|primary-shell\\|extra-session\\|stale-primary\\)")'
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
- Produces: unchanged project/session command behavior on Eshell buffers.

- [ ] **Step 1: Replace the real-Bash project-root test with a real-Eshell root test**

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

Delete project-shell assertions for `shell--start-prog`, `CHERE_INVOKING`, and `shell-resync-dirs`; generic Windows `M-x shell` coverage remains in platform/config tests.

- [ ] **Step 2: Strengthen the Org-associated root regression**

In `p3-project-shell-uses-associated-org-project-root`, assert all three properties:

```elisp
(with-current-buffer shell-buffer
  (should (derived-mode-p 'eshell-mode))
  (should (equal p3/project-shell-root-value associated-root))
  (should (equal (p3/project-normalize-root default-directory)
                 (p3/project-normalize-root associated-root))))
```

- [ ] **Step 3: Keep the existing public session commands backend-neutral**

Retain the existing implementations of `p3/project-shell`, `p3/project-shell-new`, `p3/project-shell-switch`, `p3/project-shell-other-window`, rename, kill, and `p3/project-shell-command-map` unless a test proves a buffer/process assumption. Change only predicates or wording that still says "Bash process".

- [ ] **Step 4: Run routing/session tests**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-project-context-test.el \
  -l test/p3-terminal-test.el \
  --eval '(ert-run-tests-batch-and-exit "p3-\\(project-shell\\|terminal-\\(extra\\|primary\\|stale\\|real-eshell\\|command-map\\)\\)")'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lisp/p3-terminal.el test/p3-project-context-test.el \
        test/p3-terminal-integration-test.el test/p3-terminal-test.el
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
- Consumes: Task 2 managed Eshell buffers; existing Consult package configuration.
- Produces: `p3/project-shell-prompt`, `p3/project-shell-mode-setup`, Emacs-29 append-history compatibility, `C-r -> consult-history`, and `eshell-syntax-highlighting` activation.

- [ ] **Step 1: Replace Bash/Starship rich-UX tests with Eshell-native RED tests**

Add:

```elisp
(ert-deftest p3-terminal-eshell-setup-uses-history-search ()
  (with-temp-buffer
    (eshell-mode)
    (setq-local p3/project-shell-root-value temporary-file-directory)
    (p3/project-shell-mode-setup)
    (should eshell-hist-ignoredups)
    (should (eq (key-binding (kbd "C-r")) #'consult-history))))

(ert-deftest p3-terminal-prompt-has-path-and-status-marker ()
  (let ((default-directory temporary-file-directory)
        (p3/project-shell-root-value temporary-file-directory)
        (eshell-last-command-status 0))
    (should (string-match-p "❯ " (p3/project-shell-prompt)))))
```

In `p3-config-terminal-test.el`, add an ownership test requiring `use-package eshell-syntax-highlighting` in `p3-config-terminal.el` and continuing to reject `vterm`.

- [ ] **Step 2: Run rich-UX tests and confirm RED**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-terminal-rich-ux-test.el \
  -l test/p3-config-terminal-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: FAIL on the new Eshell prompt/history/highlighting expectations.

- [ ] **Step 3: Implement a cheap native prompt**

Add:

```elisp
(defconst p3/project-shell-prompt-regexp "^[^❯\n]*❯ "
  "Prompt regexp for P3 Eshell buffers on Emacs versions that need it.")

(defun p3/project-shell-prompt ()
  "Return the prompt for the current P3 project Eshell."
  (let* ((root p3/project-shell-root-value)
         (directory (file-name-as-directory (expand-file-name default-directory)))
         (relative (and root
                        (file-in-directory-p directory root)
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

Do not invoke Git or Starship during prompt rendering.

- [ ] **Step 4: Implement concurrent history safely on Emacs 29 and 30+**

Add `(require 'ring)` and declarations for Eshell history variables/functions. For Emacs 29, append only the newest command so `eshell-write-history ... t` does not append the whole ring repeatedly:

```elisp
(defun p3/project-shell--append-history-compat ()
  "Append only the newest Eshell command on versions before Emacs 30."
  (when (and (not (boundp 'eshell-history-append))
             (boundp 'eshell-history-ring)
             (ring-p eshell-history-ring)
             (not (ring-empty-p eshell-history-ring)))
    (let ((latest (make-ring 1)))
      (ring-insert latest (ring-ref eshell-history-ring 0))
      (let ((eshell-history-ring latest))
        (eshell-write-history eshell-history-file-name t)))))
```

Replace `p3/project-shell-mode-setup` with Eshell-owned settings:

```elisp
(defun p3/project-shell-mode-setup ()
  "Apply P3 interactive UX to the current project Eshell."
  (setq-local eshell-prompt-function #'p3/project-shell-prompt
              eshell-prompt-regexp p3/project-shell-prompt-regexp
              eshell-hist-ignoredups t)
  (local-set-key (kbd "C-r") #'consult-history)
  (add-hook 'kill-buffer-hook #'p3/project-shell--forget-primary nil t)
  (if (boundp 'eshell-history-append)
      (setq-local eshell-history-append t)
    (setq-local eshell-save-history-on-exit nil)
    (add-hook 'eshell-pre-command-hook
              #'p3/project-shell--append-history-compat nil t)))
```

Bind the symbol `consult-history` without requiring Consult eagerly; the existing completion configuration owns its autoload/package setup.

- [ ] **Step 5: Configure syntax highlighting lazily**

At the top of `p3-config-terminal.el`, add `(require 'use-package)`. Add:

```elisp
(use-package eshell-syntax-highlighting
  :after esh-mode
  :config
  (eshell-syntax-highlighting-global-mode 1))
```

Because `esh-mode` is loaded only when Eshell is first used, this does not make shell highlighting an eager startup dependency.

- [ ] **Step 6: Add cross-version history regressions**

For Emacs 30+, assert `eshell-history-append` is buffer-local and non-nil after setup. For Emacs 29, create two temporary Eshell buffers with one shared temporary `eshell-history-file-name`, insert distinct newest commands into each `eshell-history-ring`, call `p3/project-shell--append-history-compat` in each, and assert the file contains each command exactly once.

Use concrete assertions:

```elisp
(should (= 1 (how-many "__P3_HISTORY_ONE__" (point-min) (point-max))))
(should (= 1 (how-many "__P3_HISTORY_TWO__" (point-min) (point-max))))
(should-not (re-search-forward "starship\|PS1=\|__p3_" nil t))
```

- [ ] **Step 7: Run rich-UX tests**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-terminal-rich-ux-test.el \
  -l test/p3-terminal-test.el \
  -l test/p3-config-terminal-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS.

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
- Consumes: Task 1 green feasibility gate; Task 2 Eshell project buffers.
- Produces: public global Eat integration with `eat-eshell-fallback-if-stty-not-available = t` and no private Eat API usage.

- [ ] **Step 1: Write a config-boundary RED test**

```elisp
(ert-deftest p3-config-terminal-uses-supported-eat-eshell-integration ()
  (let ((contents
         (p3-config-terminal-test--contents "lisp/p3-config-terminal.el")))
    (should (string-match-p "(use-package eat" contents))
    (should (string-match-p "eat-eshell-mode" contents))
    (should (string-match-p
             "eat-eshell-fallback-if-stty-not-available" contents))
    (should-not (string-match-p "eat--eshell-local-mode" contents))))
```

- [ ] **Step 2: Run the test and confirm RED**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-terminal-test.el \
  --eval '(ert-run-tests-batch-and-exit "p3-config-terminal-uses-supported-eat")'
```

Expected: FAIL.

- [ ] **Step 3: Configure Eat lazily in the configuration owner**

Add to `p3-config-terminal.el`:

```elisp
(use-package eat
  :after eshell
  :custom
  (eat-eshell-fallback-if-stty-not-available t)
  :config
  (eat-eshell-mode 1))
```

`p3-terminal.el` must not require Eat. The first real Eshell load activates this configuration through use-package's `:after eshell` path.

- [ ] **Step 4: Add a no-`stty` fallback regression**

With Eat installed, temporarily make `eshell-search-path` return nil for `stty`, bind `eat-eshell-fallback-if-stty-not-available` to `t`, and execute a trivial external command. Stub `y-or-n-p` to fail the test if called:

```elisp
(cl-letf (((symbol-function 'y-or-n-p)
           (lambda (&rest _)
             (ert-fail "Eat fallback must not prompt")))
          ((symbol-function 'eshell-search-path)
           (lambda (name)
             (unless (equal name "stty")
               (executable-find name)))))
  ;; send a trivial external command through the test Eshell here
  ...)
```

The body must assert the command completes and the same Eshell buffer remains usable; replace the comment above with the concrete command-send helper already introduced in `p3-terminal-integration-test.el` during implementation rather than introducing a second helper.

- [ ] **Step 5: Run config/integration tests with installed packages initialized**

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
git add lisp/p3-config-terminal.el test/p3-config-terminal-test.el \
        test/p3-terminal-integration-test.el
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
- Consumes: production P3 Eshell backend and Eat configuration.
- Produces: permanent behavioral regression coverage for terminalization and clean return to the same managed project shell.

- [ ] **Step 1: Factor one concrete foreground-command helper for integration tests**

Add to `p3-terminal-integration-test.el`:

```elisp
(defun p3-terminal-integration-test--send-command (buffer command)
  "Insert COMMAND at BUFFER's Eshell prompt and execute it synchronously."
  (with-current-buffer buffer
    (goto-char (point-max))
    (insert command)
    (eshell-send-input)))
```

Use this helper in Task 5's no-`stty` fallback test instead of duplicating command-send mechanics.

- [ ] **Step 2: Add P3-level zero/nonzero fixture tests**

Create the shell through `p3/project-shell-buffer`. Run the fixture with exit code `0`, then `7`, using the same timer technique from Task 1. After each command assert:

```elisp
(should (p3/project-shell-live-p buffer))
(should (eq buffer (p3/project-shell-buffer)))
(with-current-buffer buffer
  (should (derived-mode-p 'eshell-mode))
  (should-not (eshell-head-process)))
```

Also assert no literal `"\033["` appears in the buffer after the command returns.

- [ ] **Step 3: Add terminal-size/resize coverage**

Run the fixture once, record its positive `__P3_SIZE__COLS:ROWS` values, resize the selected test window with `window-resize`, run it again, and assert at least one dimension changes. Do not assert fixed dimensions because GitHub-hosted frames differ.

- [ ] **Step 4: Run the permanent terminal contract locally**

```bash
emacs -Q --batch -L lisp \
  --eval '(require (quote package))' \
  --eval '(package-initialize)' \
  -l test/p3-eat-feasibility-test.el \
  -l test/p3-terminal-test.el \
  --eval '(ert-run-tests-batch-and-exit "p3-\\(eat-feasibility\\|terminal-.*fixture\\|terminal-.*resize\\)")'
```

Expected: PASS.

- [ ] **Step 5: Fold the fixture into existing workflow test steps**

Keep one Eat installation per job. Load `test/p3-eat-feasibility-test.el` alongside terminal tests; do not create another workflow or second package-install step.

- [ ] **Step 6: Commit**

```bash
git add test/p3-eat-feasibility-test.el test/p3-terminal-integration-test.el \
        .github/workflows/emacs-tests.yml .github/workflows/windows-platform-tests.yml
git commit -m "test: cover project Eshell terminal contract"
```

---

### Task 7: Remove Displaced Project-Shell Comint/Bash/Starship Machinery

**Files:**
- Modify: `lisp/p3-terminal.el`
- Modify: `test/p3-terminal-test.el`
- Modify: `test/p3-terminal-integration-test.el`
- Modify: `test/p3-terminal-rich-ux-test.el`
- Delete: `templates/p3-starship.toml` only after the search step below proves it has no runtime consumer
- Verify unchanged behavior: `lisp/p3-platform.el`
- Verify unchanged behavior: `test/p3-config-terminal-windows-test.el`
- Verify unchanged behavior: `test/p3-platform-test.el`

**Interfaces:**
- Consumes: green Eshell lifecycle, rich UX, and Eat contract.
- Produces: one project-shell implementation with no dead Comint/Bash compatibility layer.

- [ ] **Step 1: Search every displaced runtime dependency before deletion**

```bash
git grep -nE 'project-shell-prompt-init-command|project-shell-rich-terminfo|project-shell-comint-terminal|p3-starship|STARSHIP_CONFIG|shell-dirstack-query|CHERE_INVOKING|shell-eval-command' -- ':!docs/superpowers/**'
```

Any `p3-platform.el` hit belonging to ordinary `M-x shell` stays. Project-shell-only hits are removed in Step 2.

- [ ] **Step 2: Remove project-shell-only Comint/Bash code**

Delete these project-shell implementation pieces from `p3-terminal.el`:

```text
(require 'shell)
(require 'p3-platform)                    if no non-shell reference remains
(defvar explicit-bash.exe-args)
p3/project-shell-prompt-pattern           old Comint regexp
p3/project-shell-prompt-init-command      injected Bash bootstrap
p3/project-shell-starship-config
p3/project-shell-rich-terminfo-p
p3/project-shell-comint-terminal
Comint input/history bindings
p3/windows-p project-shell directory setup
p3/platform-bash-program project-shell startup
explicit-shell-file-name / explicit-bash-args bindings
comint-terminfo-terminal project-shell binding
shell-fontify-input-enable binding
shell-highlight-undef-enable binding
shell-prompt-pattern binding
STARSHIP_CONFIG mutation
HISTFILE mutation
CHERE_INVOKING mutation
(shell ...)
(shell-eval-command ...)
```

Do not edit `p3/windows-configure-shell` or `p3/windows-shell-mode-setup` in `p3-platform.el`.

- [ ] **Step 3: Delete the tracked Starship file only after a clean consumer search**

```bash
git grep -n 'p3-starship.toml' -- ':!docs/superpowers/**'
```

Expected before deletion: only the file itself or obsolete tests being removed in this task. After removing those tests:

```bash
git rm templates/p3-starship.toml
git grep -n 'p3-starship.toml' -- ':!docs/superpowers/**' || true
```

Expected final result: no runtime/test matches.

- [ ] **Step 4: Remove Bash-specific project-shell tests and retain generic Windows shell tests**

Delete assertions whose only contract is Bash `--noediting -i`, Starship, rich Comint terminfo, Bash `HISTFILE`/`histappend`, project-shell `CHERE_INVOKING`, or project-shell `shell-resync-dirs`.

Then run the existing generic Windows shell boundary tests unchanged on a Windows runner in the final gate; their continued presence prevents this cleanup from erasing ordinary `M-x shell` behavior.

- [ ] **Step 5: Run focused cleanup regressions**

On GNU/Linux:

```bash
emacs -Q --batch -L lisp \
  --eval '(require (quote package))' \
  --eval '(package-initialize)' \
  -l test/p3-platform-test.el \
  -l test/p3-terminal-test.el \
  -l test/p3-config-terminal-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lisp/p3-terminal.el test/p3-terminal-test.el \
        test/p3-terminal-integration-test.el test/p3-terminal-rich-ux-test.el
git add -u templates/p3-starship.toml
git commit -m "refactor: retire project Bash shell machinery"
```

---

### Task 8: Final Architecture and Acceptance Verification

**Files:**
- Modify: `.github/workflows/emacs-tests.yml`
- Modify: `.github/workflows/windows-platform-tests.yml`
- Modify: `test/p3-config-terminal-test.el`
- Modify: `test/p3-integration-cleanup-test.el`

**Interfaces:**
- Consumes: all previous tasks.
- Produces: merge-ready cross-platform project-shell implementation and final verification evidence.

- [ ] **Step 1: Add architecture assertions preventing a second shell stack from returning**

Extend `p3-config-terminal-uses-one-project-shell-surface` so it continues to require `C-x C-u`/`C-c T`, rejects `vterm`, and verifies the project-shell behavior module no longer invokes Shell-mode:

```elisp
(let ((terminal (p3-config-terminal-test--contents "lisp/p3-terminal.el")))
  (should-not (string-match-p "(require 'shell)" terminal))
  (should-not (string-match-p "(shell " terminal))
  (should-not (string-match-p "shell-eval-command" terminal)))
```

Keep separate assertions that `p3-config-terminal.el` owns `use-package eat` and `use-package eshell-syntax-highlighting`.

- [ ] **Step 2: Run strict byte compilation**

```bash
emacs -Q --batch -L lisp \
  --eval '(require (quote use-package-ensure))' \
  --eval '(setq use-package-ensure-function (lambda (&rest _) t))' \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile \
  lisp/p3-terminal.el \
  lisp/p3-config-terminal.el
```

Expected: no warnings or errors.

- [ ] **Step 3: Run the complete relevant Linux shell/project regression set locally**

```bash
emacs -Q --batch -L lisp \
  --eval '(require (quote package))' \
  --eval '(package-initialize)' \
  -l test/p3-platform-test.el \
  -l test/p3-project-test.el \
  -l test/p3-project-context-test.el \
  -l test/p3-config-project-test.el \
  -l test/p3-eat-feasibility-test.el \
  -l test/p3-terminal-test.el \
  -l test/p3-config-terminal-test.el \
  -l test/p3-integration-cleanup-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: zero unexpected failures.

- [ ] **Step 4: Run the Linux manual Codex acceptance smoke**

From a real project buffer:

```text
C-x C-u
codex
```

Verify all of these manually: exactly one initial Eshell prompt; Codex renders as a usable TUI; keyboard input and resize work; exiting Codex returns to the same editable Eshell; `C-x C-u` toggles back to the previous buffer; invoking it again reuses the same project shell.

- [ ] **Step 5: Run the native-Windows manual Codex acceptance smoke**

Repeat Step 4 in native Windows Emacs with the normal Rtools/MSYS2 environment. After Codex exits, also run:

```text
git --version
bash -lc "pwd"
```

Both commands must resolve successfully from the configured environment while the project-shell surface itself remains Eshell.

- [ ] **Step 6: Run final cleanup searches**

```bash
git grep -nE 'vterm|ble\.sh|project-shell-prompt-init-command|p3-starship|STARSHIP_CONFIG' -- ':!docs/superpowers/**' || true
git grep -n 'p3/project-shell' lisp test
```

Every runtime hit for retired project-shell machinery is a failure. Historical design/spec references under `docs/superpowers/` are excluded intentionally.

- [ ] **Step 7: Commit final architecture/test adjustments**

```bash
git add .github/workflows/emacs-tests.yml \
        .github/workflows/windows-platform-tests.yml \
        test/p3-config-terminal-test.el \
        test/p3-integration-cleanup-test.el
git commit -m "test: finalize Eshell project shell migration"
```

- [ ] **Step 8: Trigger one final Linux/native-Windows CI run**

Mark the draft PR ready for review. Require all of the following before merge:

```text
Linux strict byte compilation: PASS
Linux full repository ERT workflow: PASS
Linux Eat/Eshell fixture gate: PASS
Windows boundary compilation: PASS
Windows platform/config ERT workflow: PASS
Windows Eat/Eshell fixture gate: PASS
Linux manual Codex smoke: PASS
Native-Windows manual Codex smoke: PASS
```

Do not claim the migration complete until all eight checks are satisfied.
