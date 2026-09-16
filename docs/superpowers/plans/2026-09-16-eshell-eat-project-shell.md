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
- Create: `test/p3-terminal-test-support.el`
- Create: `test/p3-eat-feasibility-test.el`
- Modify: `.github/workflows/emacs-tests.yml`
- Modify: `.github/workflows/windows-platform-tests.yml`

**Interfaces:**
- Consumes: the existing Windows MSYS2 test environment exposed through `P3_TEST_MSYS2_ROOT`; upstream public `eat-eshell-mode`.
- Produces: `p3-terminal-test-support-prepare-platform`, `p3-terminal-test-support-python`, and `p3-terminal-test-support-run-fixture`; a binary feasibility decision. Tasks 2-7 are blocked until both platform gates pass.

- [ ] **Step 1: Add the deterministic terminal program**

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
sys.stdout.write("\x1b[?1049h\x1b[2J\x1b[H__P3_TOP__")
sys.stdout.write("\x1b[2;5H__P3_CURSOR__")
sys.stdout.flush()
byte = sys.stdin.buffer.read(1)
sys.stdout.write("\x1b[?1049l")
sys.stdout.flush()
print(f"__P3_INPUT__{byte.hex()}", flush=True)
sys.exit(exit_code)
```

- [ ] **Step 2: Add shared terminal-test support**

Create `test/p3-terminal-test-support.el`:

```elisp
;;; p3-terminal-test-support.el --- Shared terminal test helpers -*- lexical-binding: t; -*-

(require 'ert)
(require 'eshell)
(require 'esh-proc)
(require 'p3-platform)

(defconst p3-terminal-test-support-root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(defun p3-terminal-test-support-python ()
  (or (executable-find "python3")
      (executable-find "python")
      (ert-skip "Python is unavailable for terminal fixture")))

(defun p3-terminal-test-support-prepare-platform ()
  (when (eq system-type 'windows-nt)
    (let* ((msys-root
            (or (getenv "P3_TEST_MSYS2_ROOT")
                (ert-skip "P3_TEST_MSYS2_ROOT is required on Windows")))
           (usr-bin (file-name-as-directory
                     (expand-file-name "usr/bin" msys-root))))
      (setq linuxy-environment-path usr-bin)
      (p3/windows-path-prepend usr-bin))))

(defun p3-terminal-test-support-run-fixture (buffer exit-code)
  "Run the terminal fixture in BUFFER and return an observation plist."
  (let* ((fixture (expand-file-name "test/fixtures/p3-terminal-fixture.py"
                                    p3-terminal-test-support-root))
         (python (p3-terminal-test-support-python))
         (command (mapconcat #'shell-quote-argument
                             (list python fixture (number-to-string exit-code))
                             " "))
         timer
         timeout-timer
         observed-terminal
         observed-raw-escape
         input-sent)
    (setq timer
          (run-at-time
           0.05 0.05
           (lambda ()
             (when (buffer-live-p buffer)
               (with-current-buffer buffer
                 (when-let ((proc (eshell-head-process)))
                   (save-excursion
                     (goto-char (point-min))
                     (when (search-forward "__P3_CURSOR__" nil t)
                       (setq observed-terminal t)
                       (goto-char (point-min))
                       (setq observed-raw-escape
                             (search-forward "\033[" nil t))
                       (process-send-string proc "x")
                       (setq input-sent t)
                       (cancel-timer timer)))))))))
    (setq timeout-timer
          (run-at-time
           5 nil
           (lambda ()
             (when (buffer-live-p buffer)
               (with-current-buffer buffer
                 (when-let ((proc (eshell-head-process)))
                   (delete-process proc)))))))
    (unwind-protect
        (progn
          (with-current-buffer buffer
            (goto-char (point-max))
            (insert command)
            (eshell-send-input))
          (with-current-buffer buffer
            (let (tty size input)
              (save-excursion
                (goto-char (point-min))
                (when (re-search-forward "__P3_TTY__\\([01]:[01]\\)" nil t)
                  (setq tty (match-string-no-properties 1)))
                (goto-char (point-min))
                (when (re-search-forward
                       "__P3_SIZE__\\([0-9]+\\):\\([0-9]+\\)" nil t)
                  (setq size (cons (string-to-number
                                    (match-string-no-properties 1))
                                   (string-to-number
                                    (match-string-no-properties 2)))))
                (goto-char (point-min))
                (when (re-search-forward "__P3_INPUT__\\([0-9a-f]+\\)" nil t)
                  (setq input (match-string-no-properties 1))))
              (list :terminal observed-terminal
                    :raw-escape observed-raw-escape
                    :input-sent input-sent
                    :tty tty
                    :size size
                    :input input))))
      (when (timerp timer) (cancel-timer timer))
      (when (timerp timeout-timer) (cancel-timer timeout-timer)))))

(provide 'p3-terminal-test-support)
```

- [ ] **Step 3: Write the feasibility ERT gate without changing production shell code**

Create `test/p3-eat-feasibility-test.el`:

```elisp
;;; p3-eat-feasibility-test.el --- Eat/Eshell platform gate -*- lexical-binding: t; -*-

(require 'ert)
(require 'eat)
(require 'p3-terminal-test-support)

(ert-deftest p3-eat-feasibility-supported-eshell-terminal-path ()
  (p3-terminal-test-support-prepare-platform)
  (should (executable-find "stty"))
  (should (executable-find "env"))
  (should (executable-find "sh"))
  (let* ((eshell-buffer-name "*p3-eat-feasibility*")
         (eat-eshell-fallback-if-stty-not-available t)
         (buffer (save-window-excursion (eshell))))
    (unwind-protect
        (progn
          (eat-eshell-mode 1)
          (let ((result (p3-terminal-test-support-run-fixture buffer 0)))
            (should (plist-get result :terminal))
            (should-not (plist-get result :raw-escape))
            (should (plist-get result :input-sent))
            (should (equal (plist-get result :tty) "1:1"))
            (should (equal (plist-get result :input) "78"))
            (should (> (car (plist-get result :size)) 0))
            (should (> (cdr (plist-get result :size)) 0))))
      (when (buffer-live-p buffer)
        (let ((kill-buffer-query-functions nil))
          (kill-buffer buffer))))))
```

- [ ] **Step 4: Run the gate locally on GNU/Linux**

```bash
rm -rf /tmp/p3-eat-elpa
emacs -Q --batch \
  --eval '(require (quote package))' \
  --eval '(setq package-user-dir "/tmp/p3-eat-elpa")' \
  --eval '(setq package-archives (quote (("nongnu" . "https://elpa.nongnu.org/nongnu/"))))' \
  --eval '(package-initialize)' \
  --eval '(package-refresh-contents)' \
  --eval '(package-install (quote eat))'

emacs -Q --batch -L lisp -L test \
  --eval '(require (quote package))' \
  --eval '(setq package-user-dir "/tmp/p3-eat-elpa")' \
  --eval '(package-initialize)' \
  -l test/p3-eat-feasibility-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS.

- [ ] **Step 5: Add the Linux CI gate**

Add before the regular ERT suite in `.github/workflows/emacs-tests.yml`:

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
          emacs -Q --batch -L lisp -L test \
            --eval '(require (quote package))' \
            --eval '(package-initialize)' \
            -l test/p3-eat-feasibility-test.el \
            -f ert-run-tests-batch-and-exit
```

The current Linux workflow uses `paths-ignore`, so no trigger change is needed.

- [ ] **Step 6: Add the native-Windows CI gate**

In the existing `Locate Git for Windows MSYS2 root` step, add:

```powershell
foreach ($tool in @("stty.exe", "env.exe", "sh.exe")) {
  if (-not (Test-Path (Join-Path $gitRoot "usr/bin/$tool"))) {
    throw "Git for Windows MSYS2 $tool not found under $gitRoot"
  }
}
```

Add these paths to the Windows workflow trigger:

```yaml
      - "test/p3-eat-feasibility-test.el"
      - "test/p3-terminal-test-support.el"
      - "test/fixtures/p3-terminal-fixture.py"
```

Add these steps:

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
          emacs -Q --batch -L lisp -L test
          --eval '(require (quote package))'
          --eval '(package-initialize)'
          -l test/p3-eat-feasibility-test.el
          -f ert-run-tests-batch-and-exit
```

- [ ] **Step 7: Commit only the spike and run the gate**

```bash
git add test/fixtures/p3-terminal-fixture.py \
        test/p3-terminal-test-support.el \
        test/p3-eat-feasibility-test.el \
        .github/workflows/emacs-tests.yml \
        .github/workflows/windows-platform-tests.yml
git commit -m "test: gate Eat Eshell terminal support"
```

Open the implementation PR as draft, then mark it ready once to trigger Linux and Windows CI.

**STOP CONDITION:** If native Windows cannot execute Eat's supported process wrapper, establish an interactive TTY, render the fixture, or return cleanly to Eshell, stop this plan. Leave production `p3-terminal.el` on the current Comint/Bash backend and return to design to choose another terminal-emulation backend. Do not continue to Task 2.

After both jobs pass, convert the PR back to draft so implementation commits do not trigger another full run until Task 7.

---

### Task 2: Redefine Project-Shell Lifecycle Around Managed Eshell Buffers

**Files:**
- Modify: `test/p3-terminal-test.el`
- Modify: `test/p3-terminal-integration-test.el`
- Modify: `lisp/p3-terminal.el`

**Interfaces:**
- Consumes: `p3/project-shell-root`, `p3/project-normalize-root`, dynamically bound `eshell-buffer-name`, public `eshell`.
- Produces: buffer-backed `p3/project-shell-buffer-p`, `p3/project-shell-live-p`, `p3/project-shell--start`, and test helper `p3-terminal-integration-test--send-command`.

- [ ] **Step 1: Write RED buffer-lifecycle tests**

Replace the process-liveness test and dead-process restart expectation with:

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
```

- [ ] **Step 2: Run the new liveness selector and confirm RED**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-terminal-test.el \
  --eval '(ert-run-tests-batch-and-exit "p3-terminal-project-shell-live-p")'
```

Expected: FAIL because current liveness requires `get-buffer-process`.

- [ ] **Step 3: Implement lazy Eshell startup and buffer-backed liveness**

Do not add a top-level `(require 'eshell)`. Add:

```elisp
(defvar eshell-buffer-name)
(declare-function eshell "eshell" (&optional arg))
```

Replace startup/liveness with:

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

- [ ] **Step 4: Clear the primary mapping when its buffer is killed**

Add:

```elisp
(defun p3/project-shell--forget-primary ()
  "Forget the current buffer if it owns its project's primary mapping."
  (when-let ((root p3/project-shell-root-value))
    (when (eq (gethash root p3/project-shell-buffers) (current-buffer))
      (remhash root p3/project-shell-buffers))))
```

Add it buffer-locally from `p3/project-shell-mode-setup`:

```elisp
(add-hook 'kill-buffer-hook #'p3/project-shell--forget-primary nil t)
```

- [ ] **Step 5: Add real idle/reuse/process-exit regressions and one shared command helper**

Add to `test/p3-terminal-integration-test.el`:

```elisp
(defun p3-terminal-integration-test--send-command (buffer command)
  "Insert COMMAND at BUFFER's Eshell prompt and execute it synchronously."
  (with-current-buffer buffer
    (goto-char (point-max))
    (insert command)
    (eshell-send-input)))

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

(ert-deftest p3-terminal-external-process-exit-keeps-project-shell-live ()
  (let ((p3/project-shell-buffers (make-hash-table :test #'equal))
        (root (file-name-as-directory temporary-file-directory)))
    (cl-letf (((symbol-function 'p3/project-shell-root) (lambda () root)))
      (let ((buffer (p3/project-shell-buffer)))
        (unwind-protect
            (progn
              (p3-terminal-integration-test--send-command buffer "git --version")
              (should (p3/project-shell-live-p buffer))
              (should (eq buffer (p3/project-shell-buffer))))
          (kill-buffer buffer))))))
```

Keep the existing killed-primary replacement test, updating only its backend assumptions.

- [ ] **Step 6: Run lifecycle tests**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-terminal-test.el \
  --eval '(ert-run-tests-batch-and-exit "p3-terminal-\\(project-shell-live-p\\|idle-primary\\|external-process-exit\\|primary-shell\\|extra-session\\|stale-primary\\)")'
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lisp/p3-terminal.el test/p3-terminal-test.el test/p3-terminal-integration-test.el
git commit -m "refactor: back project shells with Eshell buffers"
```

---

### Task 3: Preserve Project Routing and Public Session Commands

**Files:**
- Modify: `test/p3-project-context-test.el`
- Modify: `test/p3-terminal-integration-test.el`
- Modify: `lisp/p3-terminal.el`

**Interfaces:**
- Consumes: Task 2 managed Eshell lifecycle.
- Produces: unchanged public project/session behavior backed by Eshell buffers.

- [ ] **Step 1: Replace the real-Bash root test with a real-Eshell root test**

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

Remove project-shell assertions for `shell--start-prog`, `CHERE_INVOKING`, and `shell-resync-dirs`; ordinary Windows `M-x shell` remains separately covered.

- [ ] **Step 2: Strengthen the Org-associated project regression**

After obtaining the P3 project-shell buffer in `p3-project-shell-uses-associated-org-project-root`, assert:

```elisp
(with-current-buffer shell-buffer
  (should (derived-mode-p 'eshell-mode))
  (should (equal p3/project-shell-root-value associated-root))
  (should (equal (p3/project-normalize-root default-directory)
                 (p3/project-normalize-root associated-root))))
```

- [ ] **Step 3: Keep the public commands backend-neutral**

The bodies of `p3/project-shell`, `p3/project-shell-new`, `p3/project-shell-switch`, `p3/project-shell-other-window`, `p3/project-shell-rename`, `p3/project-shell-kill`, and `p3/project-shell-command-map` remain structurally unchanged. Update docstrings from “Bash shell” to “project shell” or “project Eshell”; do not change bindings or session semantics.

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
git add lisp/p3-terminal.el test/p3-project-context-test.el test/p3-terminal-integration-test.el
git commit -m "test: preserve project shell routing under Eshell"
```

---

### Task 4: Restore Prompt, History, Completion, and Input Highlighting

**Files:**
- Modify: `lisp/p3-terminal.el`
- Modify: `lisp/p3-config-terminal.el`
- Modify: `test/p3-terminal-rich-ux-test.el`
- Modify: `test/p3-config-terminal-test.el`

**Interfaces:**
- Consumes: Task 2 managed Eshell buffers; existing Consult autoload/package ownership.
- Produces: `p3/project-shell-prompt`, Eshell-owned `p3/project-shell-mode-setup`, Emacs-29 append-history compatibility, `C-r -> consult-history`, and lazy `eshell-syntax-highlighting` activation.

- [ ] **Step 1: Write RED Eshell-native UX tests**

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

Add a config test asserting `p3-config-terminal.el` contains `(use-package eshell-syntax-highlighting` and still contains no vterm declaration.

- [ ] **Step 2: Run the UX tests and confirm RED**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-terminal-rich-ux-test.el \
  -l test/p3-config-terminal-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: FAIL.

- [ ] **Step 3: Implement the native P3 prompt**

Add:

```elisp
(defconst p3/project-shell-prompt-regexp "^[^❯]*❯ "
  "Prompt regexp for P3 Eshell buffers.")

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

P3 controls the generated prompt text, so matching up to the unique `❯` terminator is sufficient; do not run Git or Starship while rendering it.

- [ ] **Step 4: Implement concurrent history on Emacs 29 and 30+**

Add `(require 'ring)` plus declarations for the Eshell history variables/functions used below. Add:

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

Replace `p3/project-shell-mode-setup` with:

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

Do not require Consult eagerly; binding the autoloaded command symbol is enough.

- [ ] **Step 5: Configure syntax highlighting lazily**

Add `(require 'use-package)` to `p3-config-terminal.el`, then:

```elisp
(use-package eshell-syntax-highlighting
  :after esh-mode
  :config
  (eshell-syntax-highlighting-global-mode 1))
```

- [ ] **Step 6: Add exact cross-version history regressions**

For Emacs 30+:

```elisp
(when (boundp 'eshell-history-append)
  (with-temp-buffer
    (eshell-mode)
    (setq-local p3/project-shell-root-value temporary-file-directory)
    (p3/project-shell-mode-setup)
    (should (local-variable-p 'eshell-history-append))
    (should eshell-history-append)))
```

For Emacs 29, construct two one-item rings containing `__P3_HISTORY_ONE__` and `__P3_HISTORY_TWO__`, bind a shared temporary `eshell-history-file-name`, call `p3/project-shell--append-history-compat` once from each buffer, then read the file into a temp buffer and assert:

```elisp
(should (= 1 (how-many "__P3_HISTORY_ONE__" (point-min) (point-max))))
(should (= 1 (how-many "__P3_HISTORY_TWO__" (point-min) (point-max))))
(should-not (re-search-forward "starship\|PS1=\|__p3_" nil t))
```

- [ ] **Step 7: Run rich-UX tests and commit**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-terminal-rich-ux-test.el \
  -l test/p3-terminal-test.el \
  -l test/p3-config-terminal-test.el \
  -f ert-run-tests-batch-and-exit

git add lisp/p3-terminal.el lisp/p3-config-terminal.el \
        test/p3-terminal-rich-ux-test.el test/p3-config-terminal-test.el
git commit -m "feat: restore rich project Eshell UX"
```

Expected: PASS before the commit.

---

### Task 5: Enable Supported Eat Integration with Deterministic Fallback

**Files:**
- Modify: `lisp/p3-config-terminal.el`
- Modify: `test/p3-config-terminal-test.el`
- Modify: `test/p3-terminal-integration-test.el`

**Interfaces:**
- Consumes: green Task 1 gate; `p3-terminal-integration-test--send-command` from Task 2.
- Produces: public global Eat integration with `eat-eshell-fallback-if-stty-not-available = t` and no private Eat API usage.

- [ ] **Step 1: Write the config-boundary RED test**

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

- [ ] **Step 2: Run it and confirm RED**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-terminal-test.el \
  --eval '(ert-run-tests-batch-and-exit "p3-config-terminal-uses-supported-eat")'
```

Expected: FAIL.

- [ ] **Step 3: Configure Eat lazily in the configuration owner**

Add:

```elisp
(use-package eat
  :after eshell
  :custom
  (eat-eshell-fallback-if-stty-not-available t)
  :config
  (eat-eshell-mode 1))
```

`p3-terminal.el` must not require Eat.

- [ ] **Step 4: Add a concrete no-`stty` fallback regression**

Add to `p3-terminal-integration-test.el`:

```elisp
(ert-deftest p3-terminal-eat-missing-stty-falls-back-without-prompt ()
  (require 'eat)
  (let* ((root (file-name-as-directory temporary-file-directory))
         (p3/project-shell-buffers (make-hash-table :test #'equal))
         (eat-eshell-fallback-if-stty-not-available t)
         (search-path (symbol-function 'eshell-search-path)))
    (cl-letf (((symbol-function 'p3/project-shell-root) (lambda () root))
              ((symbol-function 'y-or-n-p)
               (lambda (&rest _)
                 (ert-fail "Eat fallback must not prompt")))
              ((symbol-function 'eshell-search-path)
               (lambda (name)
                 (if (equal name "stty")
                     nil
                   (funcall search-path name)))))
      (let ((buffer (p3/project-shell-buffer)))
        (unwind-protect
            (progn
              (eat-eshell-mode 1)
              (p3-terminal-integration-test--send-command
               buffer "git --version")
              (should (p3/project-shell-live-p buffer))
              (should (eq buffer (p3/project-shell-buffer))))
          (kill-buffer buffer))))))
```

- [ ] **Step 5: Run config/integration tests and commit**

```bash
emacs -Q --batch -L lisp -L test \
  --eval '(require (quote package))' \
  --eval '(package-initialize)' \
  -l test/p3-config-terminal-test.el \
  -l test/p3-terminal-integration-test.el \
  -f ert-run-tests-batch-and-exit

git add lisp/p3-config-terminal.el test/p3-config-terminal-test.el \
        test/p3-terminal-integration-test.el
git commit -m "feat: add Eat terminal emulation to project Eshell"
```

Expected: PASS before the commit.

---

### Task 6: Make the Terminal Fixture a Permanent P3 Regression

**Files:**
- Modify: `test/p3-terminal-integration-test.el`
- Modify: `.github/workflows/emacs-tests.yml`
- Modify: `.github/workflows/windows-platform-tests.yml`

**Interfaces:**
- Consumes: `p3-terminal-test-support-run-fixture` from Task 1; production P3 Eshell backend and Eat integration.
- Produces: P3-level regression coverage for alternate-screen rendering, raw input, TTY dimensions, clean exit, nonzero exit, resize, and shell-buffer reuse.

- [ ] **Step 1: Add the P3-level fixture runner test**

Require the support module from `p3-terminal-integration-test.el` and add:

```elisp
(ert-deftest p3-terminal-eat-fixture-returns-to-same-project-shell ()
  (p3-terminal-test-support-prepare-platform)
  (let ((root (file-name-as-directory temporary-file-directory))
        (p3/project-shell-buffers (make-hash-table :test #'equal)))
    (cl-letf (((symbol-function 'p3/project-shell-root) (lambda () root)))
      (let ((buffer (p3/project-shell-buffer)))
        (unwind-protect
            (progn
              (dolist (exit-code '(0 7))
                (let ((result
                       (p3-terminal-test-support-run-fixture buffer exit-code)))
                  (should (plist-get result :terminal))
                  (should-not (plist-get result :raw-escape))
                  (should (equal (plist-get result :tty) "1:1"))
                  (should (equal (plist-get result :input) "78"))
                  (should (> (car (plist-get result :size)) 0))
                  (should (> (cdr (plist-get result :size)) 0))))
              (should (p3/project-shell-live-p buffer))
              (should (eq buffer (p3/project-shell-buffer)))
              (with-current-buffer buffer
                (should-not (eshell-head-process))))
          (kill-buffer buffer))))))
```

- [ ] **Step 2: Add resize coverage with a real displayed shell window**

Add:

```elisp
(ert-deftest p3-terminal-eat-fixture-tracks-window-resize ()
  (p3-terminal-test-support-prepare-platform)
  (let ((root (file-name-as-directory temporary-file-directory))
        (p3/project-shell-buffers (make-hash-table :test #'equal))
        test-window)
    (cl-letf (((symbol-function 'p3/project-shell-root) (lambda () root)))
      (let ((buffer (p3/project-shell-buffer)))
        (unwind-protect
            (progn
              (setq test-window (split-window-below))
              (set-window-buffer test-window buffer)
              (with-selected-window test-window
                (let ((before
                       (plist-get
                        (p3-terminal-test-support-run-fixture buffer 0)
                        :size)))
                  (window-resize test-window -2)
                  (let ((after
                         (plist-get
                          (p3-terminal-test-support-run-fixture buffer 0)
                          :size)))
                    (should-not (equal before after))))))
          (when (window-live-p test-window) (delete-window test-window))
          (when (buffer-live-p buffer) (kill-buffer buffer)))))))
```

- [ ] **Step 3: Run the permanent terminal contract**

```bash
emacs -Q --batch -L lisp -L test \
  --eval '(require (quote package))' \
  --eval '(package-initialize)' \
  -l test/p3-terminal-test.el \
  --eval '(ert-run-tests-batch-and-exit "p3-terminal-eat-fixture")'
```

Expected: PASS.

- [ ] **Step 4: Keep one Eat install and one fixture gate per CI job**

In both workflows, retain the Task 1 Eat installation step. Add `-L test` and ensure the normal terminal test invocation loads the support file through `require`; do not add a second Eat installation or a second workflow.

- [ ] **Step 5: Commit**

```bash
git add test/p3-terminal-integration-test.el \
        .github/workflows/emacs-tests.yml \
        .github/workflows/windows-platform-tests.yml
git commit -m "test: cover project Eshell terminal contract"
```

---

### Task 7: Remove Old Project-Shell Machinery and Perform Final Verification

**Files:**
- Modify: `lisp/p3-terminal.el`
- Modify: `test/p3-terminal-test.el`
- Modify: `test/p3-terminal-integration-test.el`
- Modify: `test/p3-terminal-rich-ux-test.el`
- Modify: `test/p3-config-terminal-test.el`
- Modify: `test/p3-integration-cleanup-test.el`
- Modify: `.github/workflows/emacs-tests.yml`
- Modify: `.github/workflows/windows-platform-tests.yml`
- Delete: `templates/p3-starship.toml` after the consumer search is clean
- Verify unchanged: `lisp/p3-platform.el`
- Verify unchanged: `test/p3-config-terminal-windows-test.el`
- Verify unchanged: `test/p3-platform-test.el`

**Interfaces:**
- Consumes: green Tasks 1-6.
- Produces: one Eshell project-shell implementation, preserved ordinary Windows `M-x shell`, final Linux/native-Windows CI evidence, and manual Codex acceptance evidence.

- [ ] **Step 1: Search all displaced runtime dependencies before deletion**

```bash
git grep -nE 'project-shell-prompt-init-command|project-shell-rich-terminfo|project-shell-comint-terminal|p3-starship|STARSHIP_CONFIG|shell-dirstack-query|CHERE_INVOKING|shell-eval-command' -- ':!docs/superpowers/**'
```

Keep any `p3-platform.el` code belonging to ordinary `M-x shell`. Remove only project-shell-specific matches.

- [ ] **Step 2: Remove project-shell-only Comint/Bash code**

Remove from `p3-terminal.el` after the search confirms each item is project-shell-only:

```text
(require 'shell)
(require 'p3-platform) if no non-shell reference remains
(defvar explicit-bash.exe-args)
old p3/project-shell-prompt-pattern
p3/project-shell-prompt-init-command
p3/project-shell-starship-config
p3/project-shell-rich-terminfo-p
p3/project-shell-comint-terminal
Comint input/history setup
project-shell p3/windows-p directory setup
project-shell p3/platform-bash-program startup
explicit-shell-file-name and explicit-bash-args bindings
comint-terminfo-terminal binding
shell-fontify-input-enable binding
shell-highlight-undef-enable binding
shell-prompt-pattern binding
STARSHIP_CONFIG mutation
HISTFILE mutation
CHERE_INVOKING mutation
shell invocation
shell-eval-command invocation
```

Do not edit `p3/windows-configure-shell` or `p3/windows-shell-mode-setup` in `p3-platform.el`.

- [ ] **Step 3: Remove obsolete Bash/Starship tests and tracked prompt file**

Delete tests whose only contract is Bash `--noediting -i`, Starship initialization/fallback, rich Comint terminfo, Bash `HISTFILE`/`histappend`, project-shell `CHERE_INVOKING`, or project-shell `shell-resync-dirs`.

Then verify and remove the file:

```bash
git grep -n 'p3-starship.toml' -- ':!docs/superpowers/**'
git rm templates/p3-starship.toml
git grep -n 'p3-starship.toml' -- ':!docs/superpowers/**' || true
```

The final grep must return no runtime/test consumer.

- [ ] **Step 4: Add architecture regressions preventing a second terminal stack**

Extend `p3-config-terminal-uses-one-project-shell-surface` with:

```elisp
(let ((terminal (p3-config-terminal-test--contents "lisp/p3-terminal.el"))
      (config (p3-config-terminal-test--contents "lisp/p3-config-terminal.el")))
  (should-not (string-match-p "(require 'shell)" terminal))
  (should-not (string-match-p "(shell " terminal))
  (should-not (string-match-p "shell-eval-command" terminal))
  (should (string-match-p "(use-package eat" config))
  (should (string-match-p "(use-package eshell-syntax-highlighting" config))
  (should-not (string-match-p "vterm" config)))
```

Keep the existing binding assertions for `C-x C-u` and `C-c T`.

- [ ] **Step 5: Run strict byte compilation and the complete relevant Linux regression set**

```bash
emacs -Q --batch -L lisp \
  --eval '(require (quote use-package-ensure))' \
  --eval '(setq use-package-ensure-function (lambda (&rest _) t))' \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile \
  lisp/p3-terminal.el \
  lisp/p3-config-terminal.el

emacs -Q --batch -L lisp -L test \
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

Expected: no byte-compile warnings and zero unexpected ERT failures.

- [ ] **Step 6: Run final cleanup searches**

```bash
git grep -nE 'vterm|ble\.sh|project-shell-prompt-init-command|p3-starship|STARSHIP_CONFIG' -- ':!docs/superpowers/**' || true
git grep -n 'p3/project-shell' lisp test
```

Review every returned runtime/test hit. No retired project-shell machinery may remain.

- [ ] **Step 7: Commit the cleanup/final-test changes**

```bash
git add lisp/p3-terminal.el \
        test/p3-terminal-test.el \
        test/p3-terminal-integration-test.el \
        test/p3-terminal-rich-ux-test.el \
        test/p3-config-terminal-test.el \
        test/p3-integration-cleanup-test.el \
        .github/workflows/emacs-tests.yml \
        .github/workflows/windows-platform-tests.yml
git add -u templates/p3-starship.toml
git commit -m "refactor: finish Eshell project shell migration"
```

- [ ] **Step 8: Run manual Codex acceptance on GNU/Linux**

From a real project buffer:

```text
C-x C-u
codex
```

Verify: one initial Eshell prompt; Codex renders as a usable TUI; keyboard input and resizing work; exiting returns to the same editable Eshell; `C-x C-u` toggles back; invoking `C-x C-u` again reuses the same project shell.

- [ ] **Step 9: Run manual Codex acceptance on native Windows**

Repeat Step 8 in native Windows Emacs with the normal Rtools/MSYS2 environment. After Codex exits, run:

```text
git --version
bash -lc "pwd"
```

Both commands must resolve successfully while the project-shell surface remains Eshell.

- [ ] **Step 10: Trigger one final Linux/native-Windows CI run**

Mark the draft PR ready for review and require:

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
