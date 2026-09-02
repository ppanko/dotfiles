# Project.el Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make built-in `project.el` the single source of P3 project identity while preserving the existing R/ESS, terminal, Projectile UI, and one-/two-window workflows.

**Architecture:** Add a focused `p3-project.el` library that owns native project discovery, `.projectile` marker registration, and the shared `p3/project-root` contract. Move project helpers out of `p3-core.el`, make ESS/R/Python/terminal consumers depend on `p3-project`, and eagerly load the project foundation after Windows tool-path setup but before project-aware subsystems. Preserve `.projectile` during this PR so Projectile and `project.el` can coexist while `project.el` becomes authoritative.

**Tech Stack:** Emacs 29+, Emacs Lisp, built-in `project.el`, ERT, `use-package`, ESS/Python/vterm integration, GitHub Actions on Ubuntu and Windows.

**Spec:** `docs/superpowers/specs/2026-09-02-project-el-foundation-design.md`

## Global Constraints

- Supported Emacs baseline: **Emacs 29 or newer**.
- Built-in `project.el` is the only source of P3 project identity after this PR.
- Keep Projectile installed, enabled, and keybound; do not remove or redesign its UI in this PR.
- Keep existing `.projectile` markers; do not rename them to `.project` in this PR.
- A nested `.projectile` marker intentionally defines an inner P3 project inside an outer VCS repository.
- Python intentionally adopts that same shared inner project boundary and may therefore select a different project-local `.venv` than before this PR.
- Preserve existing ESS process/session behavior, R helper behavior, terminal behavior, and Python environment policy apart from the approved shared-root semantic change.
- Preserve the normal one- or two-window workflow; do not add `display-buffer-alist` rules or new window-management behavior.
- Do not introduce a custom project backend or a Projectile fallback path.
- On Windows, `.projectile`-only projects must support both root detection and `project-files` enumeration after the normal P3 Unix-tool path setup.
- Do not use GitHub Actions as an iterative diagnostic loop. Run targeted and full local batch tests before the final push; use CI as the final cross-platform gate.
- Do not merge without explicit user approval.

---

## File map

**Create**

- `lisp/p3-project.el` — canonical P3 project discovery and project-root helpers.
- `test/p3-project-test.el` — platform-neutral behavioral tests for native project detection and nested project semantics.
- `test/p3-project-windows-test.el` — native-Windows integration test for the platform/project file-enumeration contract.

**Modify**

- `lisp/p3-core.el` — remove project discovery; retain only shared config commands.
- `lisp/p3-ess.el` — depend directly on `p3-project`; no ESS session behavior changes.
- `lisp/p3-r-tools.el` — depend directly on `p3-project`; keep `.projectile` in generated projects.
- `lisp/p3-python.el` — depend directly on `p3-project` and use `p3/project-root` for interpreter discovery.
- `lisp/p3-terminal.el` — depend directly on `p3-project`; no terminal behavior changes.
- `test/p3-core-test.el` — remove tests for the project behavior that moves to `p3-project-test.el`.
- `test/p3-python-test.el` — replace the old separate-project-root regression with the approved shared-root behavior.
- `test/p3-config-test.el` — require visible/eager `p3-project` wiring and verify startup ordering.
- `config.org` — eagerly load `p3-project` after Windows Rtools/MSYS2 path setup and before project-aware P3 subsystems.
- `.github/workflows/emacs-tests.yml` — byte-compile and run the new project module/tests.
- `.github/workflows/windows-platform-tests.yml` — run the Windows project/platform integration test when project/platform files change.

---

### Task 1: Extract canonical project identity into `p3-project.el`

**Files:**
- Create: `lisp/p3-project.el`
- Create: `test/p3-project-test.el`
- Modify: `lisp/p3-core.el`
- Modify: `test/p3-core-test.el`

**Interfaces:**
- Consumes: built-in `project-current`, `project-root`, and `project-vc-extra-root-markers` from Emacs 29+.
- Produces: `p3/project-root () -> directory-or-nil` and `p3/use-project-root-as-default-dir () -> nil`; eager module load also registers `.projectile` in `project-vc-extra-root-markers`.

- [ ] **Step 1: Write the new project tests before creating the implementation**

Create `test/p3-project-test.el` with focused tests for delegation, marker-only projects, nested markers, and buffer-local default directories:

```emacs-lisp
;;; p3-project-test.el --- Tests for p3-project -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'project)

(defconst p3-project-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-project-test--root))

(require 'p3-project)

(defun p3-project-test--canonical-directory (directory)
  "Return DIRECTORY in the normalized form used for root comparisons."
  (file-name-as-directory (file-truename directory)))

(ert-deftest p3-project-root-delegates-to-project-el ()
  (cl-letf (((symbol-function 'project-current)
             (lambda (&optional _maybe-prompt _directory) 'fake-project))
            ((symbol-function 'project-root)
             (lambda (_project) "/tmp/native-project/")))
    (should (equal (p3/project-root) "/tmp/native-project/"))))

(ert-deftest p3-project-root-does-not-consult-projectile ()
  (cl-letf (((symbol-function 'project-current)
             (lambda (&optional _maybe-prompt _directory) nil))
            ((symbol-function 'projectile-project-root)
             (lambda () (ert-fail "Projectile must not define P3 project identity"))))
    (should-not (p3/project-root))))

(ert-deftest p3-project-marker-only-project-is-detected-from-descendant ()
  (let* ((root (make-temp-file "p3-project-marker-" t))
         (child (expand-file-name "R/subdir" root)))
    (unwind-protect
        (progn
          (make-directory child t)
          (with-temp-file (expand-file-name ".projectile" root))
          (let ((default-directory child))
            (should
             (equal (p3-project-test--canonical-directory (p3/project-root))
                    (p3-project-test--canonical-directory root)))))
      (delete-directory root t))))

(ert-deftest p3-project-inner-marker-wins-over-outer-git-root ()
  (skip-unless (executable-find "git"))
  (let* ((outer (make-temp-file "p3-project-outer-" t))
         (inner (expand-file-name "analysis" outer))
         (child (expand-file-name "R" inner)))
    (unwind-protect
        (progn
          (should (zerop (call-process "git" nil nil nil "-C" outer "init" "-q")))
          (make-directory child t)
          (with-temp-file (expand-file-name ".projectile" inner))
          (let ((default-directory child))
            (should
             (equal (p3-project-test--canonical-directory (p3/project-root))
                    (p3-project-test--canonical-directory inner)))))
      (delete-directory outer t))))

(ert-deftest p3-project-default-directory-is-buffer-local ()
  (with-temp-buffer
    (let ((original default-directory))
      (cl-letf (((symbol-function 'p3/project-root)
                 (lambda () "/tmp/project-root/")))
        (p3/use-project-root-as-default-dir)
        (should (local-variable-p 'default-directory))
        (should (equal default-directory "/tmp/project-root/"))
        (should-not (equal original default-directory))))))

(provide 'p3-project-test)

;;; p3-project-test.el ends here
```

- [ ] **Step 2: Run the new test file and verify the extraction is not implemented yet**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-project-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: FAIL while loading because `p3-project` does not exist yet.

- [ ] **Step 3: Create the minimal native project module**

Create `lisp/p3-project.el`:

```emacs-lisp
;;; p3-project.el --- Shared project identity for the personal Emacs config -*- lexical-binding: t; -*-

(require 'project)

(add-to-list 'project-vc-extra-root-markers ".projectile")

(defun p3/project-root ()
  "Return the current built-in `project.el' root, if any."
  (when-let ((project (project-current nil)))
    (project-root project)))

(defun p3/use-project-root-as-default-dir ()
  "Use the current project root as the buffer's default directory."
  (when-let ((root (p3/project-root)))
    (setq-local default-directory root)))

(provide 'p3-project)

;;; p3-project.el ends here
```

- [ ] **Step 4: Remove project ownership from `p3-core.el`**

Delete from `lisp/p3-core.el`:

```emacs-lisp
(require 'project)
(declare-function projectile-project-root "projectile")

(defun p3/project-el-root () ...)
(defun p3/project-root () ...)
(defun p3/use-project-root-as-default-dir () ...)
```

Keep the `p3/load-config` declaration and the `p3/config-visit` / `p3/config-reload` commands unchanged. The resulting module should start approximately as:

```emacs-lisp
;;; p3-core.el --- Shared helpers for the personal Emacs config -*- lexical-binding: t; -*-

(declare-function p3/load-config nil (&optional quiet))
```

- [ ] **Step 5: Reduce `p3-core-test.el` to the behavior still owned by core**

Remove these old tests from `test/p3-core-test.el`:

```text
p3-core-project-root-prefers-projectile
p3-core-project-root-falls-back-to-project-el
p3-core-project-default-directory-is-buffer-local
```

Retain the existing config-command test:

```emacs-lisp
(ert-deftest p3-core-config-commands-remain-commands ()
  (should (commandp #'p3/config-visit))
  (should (commandp #'p3/config-reload)))
```

`p3-core-test.el` no longer needs `cl-lib` after those project tests are removed; remove that require if byte-compilation confirms it is unused.

- [ ] **Step 6: Run the focused project/core tests**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-project-test.el \
  -l test/p3-core-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: all project and core tests PASS.

- [ ] **Step 7: Byte-compile the new boundary with warnings as errors**

Run:

```bash
emacs -Q --batch -L lisp \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile \
  lisp/p3-project.el \
  lisp/p3-core.el
```

Expected: exit status 0 with no warnings.

- [ ] **Step 8: Commit Task 1**

```bash
git add lisp/p3-project.el lisp/p3-core.el test/p3-project-test.el test/p3-core-test.el
git commit -m "refactor: make project.el own project identity"
```

---

### Task 2: Migrate ESS, R, Python, and terminal consumers to the shared root

**Files:**
- Modify: `lisp/p3-ess.el`
- Modify: `lisp/p3-r-tools.el`
- Modify: `lisp/p3-python.el`
- Modify: `lisp/p3-terminal.el`
- Modify: `test/p3-python-test.el`
- Verify unchanged behavior through: `test/p3-ess-test.el`, `test/p3-r-tools-test.el`, `test/p3-terminal-test.el`

**Interfaces:**
- Consumes: `p3/project-root () -> directory-or-nil` and `p3/use-project-root-as-default-dir () -> nil` from `p3-project.el`.
- Produces: no new public interface; existing subsystem commands keep their current names and behavior.

- [ ] **Step 1: Replace the obsolete Python regression with a failing shared-root unit test**

In `test/p3-python-test.el`, remove `p3-python-project-interpreter-preserves-project-el-root` and add:

```emacs-lisp
(ert-deftest p3-python-project-interpreter-uses-shared-p3-root ()
  (p3-python-test--with-temp-project root
    (let ((interpreter
           (p3-python-test--make-executable
            (expand-file-name ".venv/bin/python" root)))
          (system-type 'gnu/linux))
      (cl-letf (((symbol-function 'p3/project-root)
                 (lambda () root)))
        (should (equal (p3/python-project-interpreter) interpreter))))))
```

Update the existing `.venv`, buffer-local setup, and Windows-layout tests so they mock `p3/project-root` directly instead of separately mocking `project-current` and `project-root`.

- [ ] **Step 2: Add the nested-project Python integration test**

Add to `test/p3-python-test.el`:

```emacs-lisp
(ert-deftest p3-python-inner-project-marker-selects-inner-venv ()
  (skip-unless (executable-find "git"))
  (p3-python-test--with-temp-project outer
    (let* ((inner (expand-file-name "analysis" outer))
           (source-directory (expand-file-name "src" inner))
           (interpreter
            (p3-python-test--make-executable
             (expand-file-name ".venv/bin/python" inner)))
           (system-type 'gnu/linux))
      (should (zerop (call-process "git" nil nil nil "-C" outer "init" "-q")))
      (make-directory source-directory t)
      (with-temp-file (expand-file-name ".projectile" inner))
      (let ((default-directory source-directory))
        (should (equal (p3/python-project-interpreter) interpreter))))))
```

Ensure the test file requires `p3-project` explicitly before `p3-python` if that is not already guaranteed by `p3-python` after migration.

- [ ] **Step 3: Run the Python tests and verify they fail against the old implementation**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-project-test.el \
  -l test/p3-python-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: FAIL because `p3/python-project-interpreter` still calls the removed `p3/project-el-root` contract or does not honor the mocked shared root.

- [ ] **Step 4: Migrate the four project-aware modules**

In `lisp/p3-python.el`, replace:

```emacs-lisp
(require 'p3-core)
```

with:

```emacs-lisp
(require 'p3-project)
```

and change:

```emacs-lisp
(when-let ((root (p3/project-el-root)))
```

to:

```emacs-lisp
(when-let ((root (p3/project-root)))
```

In `lisp/p3-ess.el`, replace the `p3-core` dependency with `p3-project` and update the commentary sentence to say project identity is delegated to `p3-project`.

In `lisp/p3-r-tools.el` and `lisp/p3-terminal.el`, replace:

```emacs-lisp
(require 'p3-core)
```

with:

```emacs-lisp
(require 'p3-project)
```

Do **not** change the `.projectile` entry in `p3-r--common-project-files`.

- [ ] **Step 5: Run all project-dependent subsystem tests**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-project-test.el \
  -l test/p3-python-test.el \
  -l test/p3-ess-test.el \
  -l test/p3-r-tools-test.el \
  -l test/p3-terminal-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: all tests PASS; existing ESS/R/terminal tests continue to exercise the unchanged `p3/project-root` interface.

- [ ] **Step 6: Byte-compile all migrated modules**

Run:

```bash
emacs -Q --batch -L lisp \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile \
  lisp/p3-project.el \
  lisp/p3-ess.el \
  lisp/p3-r-tools.el \
  lisp/p3-python.el \
  lisp/p3-terminal.el
```

Expected: exit status 0 with no warnings or unresolved `p3/project-el-root` references.

- [ ] **Step 7: Verify the retired helper is gone from implementation code**

Run:

```bash
git grep -n "p3/project-el-root" -- '*.el'
```

Expected: no matches.

Run:

```bash
git grep -n "projectile-project-root" -- lisp
```

Expected: no matches in `lisp/`; Projectile may still appear in `config.org` and project scaffolding/tests because its UI and marker are intentionally retained.

- [ ] **Step 8: Commit Task 2**

```bash
git add lisp/p3-ess.el lisp/p3-r-tools.el lisp/p3-python.el lisp/p3-terminal.el test/p3-python-test.el
git commit -m "refactor: share native project roots across workflows"
```

---

### Task 3: Establish eager project-foundation startup wiring

**Files:**
- Modify: `config.org`
- Modify: `test/p3-config-test.el`

**Interfaces:**
- Consumes: eager `p3/windows-configure-rtools` platform setup and `p3-project` module from Tasks 1–2.
- Produces: startup invariant that `.projectile` is registered with `project.el` before P3 project-aware subsystem configuration can call `project-current`.

- [ ] **Step 1: Add failing config-structure assertions**

Update the module list in `p3-config-org-delegates-custom-subsystems-to-modules` so it includes `"p3-project"`:

```emacs-lisp
(dolist (module '("p3-platform" "p3-project" "p3-core" "p3-python"
                  "p3-terminal" "p3-ess" "p3-gptel"))
  ...)
```

Keep `"(defun p3/project-root"` in the implementation exclusion list so `config.org` is explicitly forbidden from reabsorbing project implementation.

Add a startup-order test:

```emacs-lisp
(ert-deftest p3-config-project-foundation-precedes-project-consumers ()
  (with-temp-buffer
    (insert-file-contents (expand-file-name "config.org" p3-config-test--root))
    (let ((rtools-position
           (progn
             (should (search-forward "(p3/windows-configure-rtools)" nil t))
             (point)))
          project-position
          core-position
          python-position
          ess-position
          terminal-position)
      (setq project-position
            (progn
              (should (search-forward "(use-package p3-project" nil t))
              (point)))
      (setq core-position
            (progn
              (should (search-forward "(use-package p3-core" nil t))
              (point)))
      (setq python-position
            (progn
              (should (search-forward "(use-package p3-python" nil t))
              (point)))
      (setq ess-position
            (progn
              (should (search-forward "(use-package p3-ess" nil t))
              (point)))
      (setq terminal-position
            (progn
              (should (search-forward "(use-package p3-terminal" nil t))
              (point)))
      (should (< rtools-position project-position))
      (should (< project-position core-position))
      (should (< project-position python-position))
      (should (< project-position ess-position))
      (should (< project-position terminal-position)))))
```

If the actual current `config.org` order makes sequential `search-forward` unsuitable for one of these consumers, compute each position independently from `point-min`; keep the assertions themselves unchanged.

- [ ] **Step 2: Run the config tests and verify the new module/order contract fails**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: FAIL because `config.org` does not yet contain `(use-package p3-project ...)`.

- [ ] **Step 3: Add the eager project foundation immediately after platform-path setup**

In `config.org`, directly after the existing eager `p3-platform` block that calls `p3/windows-configure-rtools`, add:

```emacs-lisp
#+BEGIN_SRC emacs-lisp
  (use-package p3-project
    :ensure nil
    :demand t)
#+END_SRC
```

Do not add keybindings or extra setup calls. Requiring `p3-project` is itself the startup action that registers `.projectile` in `project-vc-extra-root-markers`.

Keep the existing `p3-core` block responsible for `C-c e` / `C-c r`; do not move those commands into the project module.

- [ ] **Step 4: Run the config tests and tangle smoke test**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS, including readable `init.el`, readable tangled config, module delegation, platform ordering, and project-foundation ordering.

- [ ] **Step 5: Commit Task 3**

```bash
git add config.org test/p3-config-test.el
git commit -m "refactor: load project foundation before project workflows"
```

---

### Task 4: Add Linux and Windows regression gates for the new boundary

**Files:**
- Create: `test/p3-project-windows-test.el`
- Modify: `.github/workflows/emacs-tests.yml`
- Modify: `.github/workflows/windows-platform-tests.yml`

**Interfaces:**
- Consumes: `p3/windows-configure-rtools`, `p3/project-root`, built-in `project-current`, and `project-files`.
- Produces: CI evidence that marker-only project discovery works on Linux and that Windows project file enumeration works with a Unix-compatible MSYS2 tool directory placed first through the existing platform setup path.

- [ ] **Step 1: Write the native-Windows integration test**

Create `test/p3-project-windows-test.el`:

```emacs-lisp
;;; p3-project-windows-test.el --- Windows project/platform integration tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'seq)
(require 'project)

(defconst p3-project-windows-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-project-windows-test--root))

(require 'p3-platform)
(require 'p3-project)

(ert-deftest p3-project-windows-msys2-tools-support-marker-project-files ()
  (unless (eq system-type 'windows-nt)
    (ert-skip "Native Windows-only project enumeration contract"))
  (let* ((msys2-root (getenv "P3_TEST_MSYS2_ROOT"))
         (usr-bin (and msys2-root (expand-file-name "usr/bin" msys2-root)))
         (bash (and usr-bin (expand-file-name "bash.exe" usr-bin)))
         (find (and usr-bin (expand-file-name "find.exe" usr-bin)))
         (root (make-temp-file "p3-project-windows-" t))
         (child (expand-file-name "R" root))
         (data-file (expand-file-name "R/example.R" root))
         (old-path (getenv "PATH"))
         (old-exec-path (copy-sequence exec-path))
         (p3/windows-rtools-override msys2-root)
         (find-program "find"))
    (unwind-protect
        (progn
          (should msys2-root)
          (should (file-readable-p bash))
          (should (file-readable-p find))
          (make-directory child t)
          (with-temp-file (expand-file-name ".projectile" root))
          (with-temp-file data-file (insert "x <- 1\n"))
          (p3/windows-configure-rtools)
          (let* ((default-directory child)
                 (project (project-current nil))
                 (files (project-files project)))
            (should project)
            (should
             (equal (file-name-as-directory (file-truename (project-root project)))
                    (file-name-as-directory (file-truename root))))
            (should
             (seq-some
              (lambda (file)
                (string-equal (file-name-nondirectory file) "example.R"))
              files))))
      (setq exec-path old-exec-path)
      (setenv "PATH" old-path)
      (delete-directory root t))))

(provide 'p3-project-windows-test)

;;; p3-project-windows-test.el ends here
```

The test deliberately uses the normal `p3/windows-configure-rtools` path. CI supplies a known MSYS2-compatible root from the preinstalled Git for Windows distribution; this exercises the relevant path-ordering behavior without adding an Rtools installation to CI.

- [ ] **Step 2: Extend the normal Ubuntu Emacs test workflow**

In `.github/workflows/emacs-tests.yml`, add `lisp/p3-project.el` to the byte-compilation list before modules that require it:

```yaml
            lisp/p3-platform.el \
            lisp/p3-project.el \
            lisp/p3-core.el \
```

Add the new platform-neutral project tests to the ERT command before subsystem tests:

```yaml
            -l test/p3-config-test.el \
            -l test/p3-project-test.el \
            -l test/p3-core-test.el \
```

Do not add the Windows-only integration test to this Linux job.

- [ ] **Step 3: Expand Windows workflow path triggers narrowly**

In `.github/workflows/windows-platform-tests.yml`, keep the existing platform paths and add:

```yaml
      - "lisp/p3-project.el"
      - "test/p3-project-test.el"
      - "test/p3-project-windows-test.el"
```

This causes Windows CI to run when either half of the project/platform integration changes.

- [ ] **Step 4: Resolve a stable MSYS2 root from Git for Windows in CI**

Before running ERT in `.github/workflows/windows-platform-tests.yml`, add:

```yaml
      - name: Locate Git for Windows MSYS2 root
        shell: powershell
        run: |
          $gitExe = (Get-Command git).Source
          $gitRoot = Split-Path (Split-Path $gitExe -Parent) -Parent
          if (-not (Test-Path (Join-Path $gitRoot "usr/bin/bash.exe"))) {
            throw "Git for Windows MSYS2 bash not found under $gitRoot"
          }
          if (-not (Test-Path (Join-Path $gitRoot "usr/bin/find.exe"))) {
            throw "Git for Windows MSYS2 find not found under $gitRoot"
          }
          "P3_TEST_MSYS2_ROOT=$($gitRoot -replace '\\','/')" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
```

This is test scaffolding only. Production Windows behavior continues to discover and use Rtools through `p3-platform.el`.

- [ ] **Step 5: Extend the Windows compile/test commands**

Change the byte-compile step to compile both boundary modules:

```yaml
      - name: Byte-compile Windows boundary modules
        shell: powershell
        run: >-
          emacs -Q --batch -L lisp
          --eval "(setq byte-compile-error-on-warn t)"
          -f batch-byte-compile
          lisp/p3-platform.el
          lisp/p3-project.el
```

Change the test step to run both existing platform tests and the new Windows project integration test:

```yaml
      - name: Run Windows platform and project tests
        shell: powershell
        run: >-
          emacs -Q --batch -L lisp
          -l test/p3-platform-test.el
          -l test/p3-project-windows-test.el
          -f ert-run-tests-batch-and-exit
```

- [ ] **Step 6: Run the complete local Linux gate before pushing CI changes**

Run exactly the suite used by `.github/workflows/emacs-tests.yml` after adding the new project test:

```bash
emacs -Q --batch \
  -L lisp \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile \
  lisp/p3-platform.el \
  lisp/p3-project.el \
  lisp/p3-core.el \
  lisp/p3-python.el \
  lisp/p3-terminal.el \
  lisp/p3-ess.el \
  lisp/p3-r-tools.el \
  lisp/p3-gptel.el
```

Expected: exit status 0 and no warnings.

Then run:

```bash
emacs -Q --batch \
  -L lisp \
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
  -f ert-run-tests-batch-and-exit
```

Expected: all ERT tests PASS.

- [ ] **Step 7: Inspect the final diff for scope leakage**

Run:

```bash
git diff master...HEAD --stat
git diff master...HEAD -- \
  lisp/p3-project.el lisp/p3-core.el lisp/p3-ess.el lisp/p3-r-tools.el \
  lisp/p3-python.el lisp/p3-terminal.el config.org test .github/workflows
```

Verify all of the following before committing/pushing:

- Projectile package configuration and keybindings still exist.
- `p3-r--common-project-files` still emits `.projectile`.
- No ESS process/session implementation changed beyond its required module dependency/commentary.
- No terminal window/switching implementation changed beyond its required module dependency.
- No `display-buffer-alist` rules were added.
- No startup/tangling redesign was introduced.
- No `p3/project-el-root` implementation or references remain.

- [ ] **Step 8: Commit Task 4**

```bash
git add test/p3-project-windows-test.el .github/workflows/emacs-tests.yml .github/workflows/windows-platform-tests.yml
git commit -m "test: cover native project foundation across platforms"
```

- [ ] **Step 9: Push once and use CI as the final cross-platform gate**

Push `refactor/project-el-foundation` after the local suite is green. Confirm:

- Ubuntu `Emacs tests` passes.
- Windows `Windows platform tests` passes, including marker-only `project-files` enumeration.

If CI reveals a platform-specific failure, diagnose that exact failure locally or from the job log before pushing another change; do not add diagnostic workflow machinery.

---

## Completion criteria

PR 1 is implementation-complete only when all of these are true:

1. `p3-project.el` exclusively owns `p3/project-root` and `p3/use-project-root-as-default-dir`.
2. No P3 implementation calls `projectile-project-root` or the retired `p3/project-el-root` helper.
3. ESS, R tools, Python, and terminal code consume the same `p3/project-root` contract.
4. Existing `.projectile` projects are recognized by native `project.el`, including nested projects inside outer Git repositories.
5. Python resolves `.venv` from that shared inner root in the nested-project case.
6. `config.org` eagerly loads `p3-project` after Windows Unix-tool path setup and before project-aware P3 modules.
7. Existing R project scaffolding still creates `.projectile`.
8. The one-/two-window workflow is unchanged.
9. Linux byte-compilation and the complete ERT suite pass.
10. Native Windows project detection and `project-files` enumeration pass through the existing platform path setup.
11. The final diff contains no Projectile removal, ESS redesign, Python environment-manager redesign, Org changes, startup/tangling redesign, or buffer-layout changes.
12. The branch is not merged without explicit user approval.
