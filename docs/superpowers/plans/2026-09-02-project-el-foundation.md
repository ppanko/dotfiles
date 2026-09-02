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
- Python intentionally adopts that shared inner project boundary and may therefore select a different project-local `.venv` than before this PR.
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
- `test/p3-core-test.el` — remove project tests that move to `p3-project-test.el`.
- `test/p3-python-test.el` — replace the old separate-project-root regression with the approved shared-root behavior.
- `test/p3-r-tools-test.el` — explicitly lock in `.projectile` generation.
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
- Produces: `p3/project-root () -> directory-or-nil` and `p3/use-project-root-as-default-dir () -> nil`; loading the module registers `.projectile` in `project-vc-extra-root-markers`.

- [ ] **Step 1: Write the failing project tests**

Create `test/p3-project-test.el`:

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
  "Return DIRECTORY in normalized form for root comparisons."
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
             (lambda ()
               (ert-fail "Projectile must not define P3 project identity"))))
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
          (should
           (zerop (call-process "git" nil nil nil "-C" outer "init" "-q")))
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

- [ ] **Step 2: Run the new tests and verify the module is missing**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-project-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: FAIL while loading because `p3-project` does not exist.

- [ ] **Step 3: Create the minimal native project module**

Create `lisp/p3-project.el`:

```emacs-lisp
;;; p3-project.el --- Shared project identity for the personal Emacs config -*- lexical-binding: t; -*-

(require 'project)

(unless (boundp 'project-vc-extra-root-markers)
  (error "P3 project support requires Emacs 29 or newer"))

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

- [ ] **Step 4: Replace `p3-core.el` with the exact reduced implementation**

`lisp/p3-core.el` should contain only:

```emacs-lisp
;;; p3-core.el --- Shared helpers for the personal Emacs config -*- lexical-binding: t; -*-

(declare-function p3/load-config nil (&optional quiet))

(defun p3/config-visit ()
  "Visit the authoritative literate Emacs configuration."
  (interactive)
  (find-file
   (if (boundp 'p3/config-source)
       p3/config-source
     (expand-file-name "config.org" user-emacs-directory))))

(defun p3/config-reload ()
  "Tangle and reload the authoritative literate Emacs configuration."
  (interactive)
  (unless (fboundp 'p3/load-config)
    (user-error "Config loader is unavailable"))
  (p3/load-config))

(provide 'p3-core)

;;; p3-core.el ends here
```

- [ ] **Step 5: Reduce `p3-core-test.el` to the exact behavior still owned by core**

Replace `test/p3-core-test.el` with:

```emacs-lisp
;;; p3-core-test.el --- Tests for p3-core -*- lexical-binding: t; -*-

(require 'ert)

(defconst p3-core-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-core-test--root))

(require 'p3-core)

(ert-deftest p3-core-config-commands-remain-commands ()
  (should (commandp #'p3/config-visit))
  (should (commandp #'p3/config-reload)))

(provide 'p3-core-test)

;;; p3-core-test.el ends here
```

- [ ] **Step 6: Run the focused tests**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-project-test.el \
  -l test/p3-core-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: all project/core tests PASS.

- [ ] **Step 7: Byte-compile the new boundary**

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

### Task 2: Migrate ESS, R, Python, and terminal consumers

**Files:**
- Modify: `lisp/p3-ess.el`
- Modify: `lisp/p3-r-tools.el`
- Modify: `lisp/p3-python.el`
- Modify: `lisp/p3-terminal.el`
- Modify: `test/p3-python-test.el`
- Modify: `test/p3-r-tools-test.el`
- Verify: `test/p3-ess-test.el`, `test/p3-terminal-test.el`

**Interfaces:**
- Consumes: `p3/project-root () -> directory-or-nil` and `p3/use-project-root-as-default-dir () -> nil` from `p3-project.el`.
- Produces: no new public interface; existing subsystem commands keep their current names and behavior.

- [ ] **Step 1: Replace the obsolete Python regression with the shared-root unit test**

Remove `p3-python-project-interpreter-preserves-project-el-root` from `test/p3-python-test.el` and add:

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

Update these existing tests so they mock `p3/project-root` directly instead of `project-current`/`project-root`:

- `p3-python-project-interpreter-prefers-dot-venv`
- `p3-python-setup-project-interpreter-is-buffer-local`
- `p3-python-project-interpreter-supports-windows-venv-layout`

- [ ] **Step 2: Add the nested-project Python integration test**

Add:

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
      (should
       (zerop (call-process "git" nil nil nil "-C" outer "init" "-q")))
      (make-directory source-directory t)
      (with-temp-file (expand-file-name ".projectile" inner))
      (let ((default-directory source-directory))
        (should (equal (p3/python-project-interpreter) interpreter))))))
```

- [ ] **Step 3: Add an explicit scaffolding regression for `.projectile`**

In `p3-r-new-analysis-project-generates-expected-files`, add:

```emacs-lisp
(should (file-exists-p (expand-file-name ".projectile" root)))
```

This turns the retained marker from an implementation assumption into a tested compatibility contract.

- [ ] **Step 4: Run Python/R tests and verify the Python behavior still fails**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-project-test.el \
  -l test/p3-python-test.el \
  -l test/p3-r-tools-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: Python shared-root tests FAIL against the old implementation; the new R marker assertion already passes.

- [ ] **Step 5: Migrate the four modules to `p3-project`**

In `lisp/p3-python.el`, replace:

```emacs-lisp
(require 'p3-core)
```

with:

```emacs-lisp
(require 'p3-project)
```

and replace:

```emacs-lisp
(when-let ((root (p3/project-el-root)))
```

with:

```emacs-lisp
(when-let ((root (p3/project-root)))
```

In `lisp/p3-ess.el`, replace `(require 'p3-core)` with `(require 'p3-project)` and change the commentary sentence from:

```text
Project identity is delegated to p3-core so ESS,
Python, R helpers, and terminal workflows use the same root abstraction.
```

to:

```text
Project identity is delegated to p3-project so ESS,
Python, R helpers, and terminal workflows use the same root abstraction.
```

In both `lisp/p3-r-tools.el` and `lisp/p3-terminal.el`, replace `(require 'p3-core)` with `(require 'p3-project)`.

Do not change the `.projectile` entry in `p3-r--common-project-files`.

- [ ] **Step 6: Run all project-dependent subsystem tests**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-project-test.el \
  -l test/p3-python-test.el \
  -l test/p3-ess-test.el \
  -l test/p3-r-tools-test.el \
  -l test/p3-terminal-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: all tests PASS.

- [ ] **Step 7: Byte-compile migrated modules and search for retired references**

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

Expected: exit status 0 with no warnings.

Then:

```bash
git grep -n "p3/project-el-root" -- '*.el'
git grep -n "projectile-project-root" -- lisp
```

Expected: both commands return no implementation matches.

- [ ] **Step 8: Commit Task 2**

```bash
git add \
  lisp/p3-ess.el lisp/p3-r-tools.el lisp/p3-python.el lisp/p3-terminal.el \
  test/p3-python-test.el test/p3-r-tools-test.el
git commit -m "refactor: share native project roots across workflows"
```

---

### Task 3: Establish eager project-foundation startup wiring

**Files:**
- Modify: `config.org`
- Modify: `test/p3-config-test.el`

**Interfaces:**
- Consumes: eager `p3/windows-configure-rtools` setup and `p3-project` from Tasks 1–2.
- Produces: `.projectile` registration before any P3 project-aware subsystem configuration can invoke `project-current`.

- [ ] **Step 1: Add the failing module-delegation assertion**

Change the module list in `p3-config-org-delegates-custom-subsystems-to-modules` to:

```emacs-lisp
(dolist (module '("p3-platform" "p3-project" "p3-core" "p3-python"
                  "p3-terminal" "p3-ess" "p3-gptel"))
  (goto-char (point-min))
  (should (search-forward (format "(use-package %s" module) nil t)))
```

Keep `"(defun p3/project-root"` in the implementation exclusion list.

- [ ] **Step 2: Add a startup-order test using independent source positions**

Add this helper and test to `test/p3-config-test.el`:

```emacs-lisp
(defun p3-config-test--position-of (text)
  "Return the position immediately after TEXT in the current buffer."
  (goto-char (point-min))
  (should (search-forward text nil t))
  (point))

(ert-deftest p3-config-project-foundation-precedes-project-consumers ()
  (with-temp-buffer
    (insert-file-contents (expand-file-name "config.org" p3-config-test--root))
    (let ((rtools-position
           (p3-config-test--position-of "(p3/windows-configure-rtools)"))
          (project-position
           (p3-config-test--position-of "(use-package p3-project"))
          (core-position
           (p3-config-test--position-of "(use-package p3-core"))
          (python-position
           (p3-config-test--position-of "(use-package p3-python"))
          (ess-position
           (p3-config-test--position-of "(use-package p3-ess"))
          (terminal-position
           (p3-config-test--position-of "(use-package p3-terminal")))
      (should (< rtools-position project-position))
      (should (< project-position core-position))
      (should (< project-position python-position))
      (should (< project-position ess-position))
      (should (< project-position terminal-position)))))
```

- [ ] **Step 3: Run the config tests and verify the new contract fails**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: FAIL because `config.org` does not yet contain `(use-package p3-project ...)`.

- [ ] **Step 4: Add the eager project foundation directly after platform-path setup**

Immediately after the existing `p3-platform` block that calls `p3/windows-configure-rtools`, add:

```org
#+BEGIN_SRC emacs-lisp
  (use-package p3-project
    :ensure nil
    :demand t)
#+END_SRC
```

Do not add keybindings or setup functions. Loading `p3-project` performs the marker registration.

Keep the existing `p3-core` block responsible for `C-c e` and `C-c r`.

- [ ] **Step 5: Run config/tangle tests**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS, including readable `init.el`, readable tangled output, module delegation, existing platform ordering, and project-foundation ordering.

- [ ] **Step 6: Commit Task 3**

```bash
git add config.org test/p3-config-test.el
git commit -m "refactor: load project foundation before project workflows"
```

---

### Task 4: Add Linux and Windows regression gates

**Files:**
- Create: `test/p3-project-windows-test.el`
- Modify: `.github/workflows/emacs-tests.yml`
- Modify: `.github/workflows/windows-platform-tests.yml`

**Interfaces:**
- Consumes: `p3/windows-configure-rtools`, `p3/project-root`, built-in `project-current`, `project-root`, and `project-files`.
- Produces: final CI evidence for Linux project semantics and native-Windows marker-only file enumeration.

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
          (with-temp-file data-file
            (insert "x <- 1\n"))
          (p3/windows-configure-rtools)
          (let* ((default-directory child)
                 (project (project-current nil))
                 (files (project-files project)))
            (should project)
            (should
             (equal (file-name-as-directory
                     (file-truename (project-root project)))
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

CI will supply a known MSYS2-compatible root from Git for Windows. This exercises the existing `p3/windows-configure-rtools` path-ordering behavior without installing Rtools solely for CI.

- [ ] **Step 2: Extend the normal Ubuntu workflow**

In `.github/workflows/emacs-tests.yml`, add `p3-project.el` to byte-compilation before modules that consume it:

```yaml
            lisp/p3-platform.el \
            lisp/p3-project.el \
            lisp/p3-core.el \
```

Add `p3-project-test.el` to the ERT command:

```yaml
            -l test/p3-config-test.el \
            -l test/p3-project-test.el \
            -l test/p3-core-test.el \
```

Do not load the Windows-only integration test in this Linux job.

- [ ] **Step 3: Expand Windows workflow path triggers narrowly**

Keep the current paths and add:

```yaml
      - "lisp/p3-project.el"
      - "test/p3-project-test.el"
      - "test/p3-project-windows-test.el"
```

- [ ] **Step 4: Resolve the Git-for-Windows MSYS2 root**

Before ERT in `.github/workflows/windows-platform-tests.yml`, add:

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

Production behavior still discovers Rtools; Git for Windows is only the CI fixture providing the same `usr/bin/bash.exe` + Unix `find.exe` layout required by the path setup contract.

- [ ] **Step 5: Extend the Windows compile/test commands**

Use:

```yaml
      - name: Byte-compile Windows boundary modules
        shell: powershell
        run: >-
          emacs -Q --batch -L lisp
          --eval "(setq byte-compile-error-on-warn t)"
          -f batch-byte-compile
          lisp/p3-platform.el
          lisp/p3-project.el

      - name: Run Windows platform and project tests
        shell: powershell
        run: >-
          emacs -Q --batch -L lisp
          -l test/p3-platform-test.el
          -l test/p3-project-windows-test.el
          -f ert-run-tests-batch-and-exit
```

- [ ] **Step 6: Run the complete local Linux gate before pushing**

Byte-compile exactly the normal workflow module set plus `p3-project.el`:

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

Expected: exit status 0 with no warnings.

Run the complete ERT suite:

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

```bash
git diff master...HEAD --stat
git diff master...HEAD -- \
  lisp/p3-project.el lisp/p3-core.el lisp/p3-ess.el lisp/p3-r-tools.el \
  lisp/p3-python.el lisp/p3-terminal.el config.org test .github/workflows
```

Verify:

- Projectile package configuration and keybindings still exist.
- R project scaffolding still emits `.projectile` and the ERT assertion proves it.
- ESS process/session code changed only in dependency/commentary lines.
- Terminal switching/window code changed only in its dependency line.
- No `display-buffer-alist` rules were added.
- No startup/tangling redesign was introduced.
- No `p3/project-el-root` implementation or references remain.

- [ ] **Step 8: Commit Task 4**

```bash
git add \
  test/p3-project-windows-test.el \
  .github/workflows/emacs-tests.yml \
  .github/workflows/windows-platform-tests.yml
git commit -m "test: cover native project foundation across platforms"
```

- [ ] **Step 9: Push once and use CI as the final cross-platform gate**

Push `refactor/project-el-foundation` after the local suite is green. Confirm:

- Ubuntu `Emacs tests` passes.
- Windows `Windows platform tests` passes, including marker-only `project-files` enumeration.

If CI reveals a platform-specific failure, diagnose that exact failure from the job log before pushing another change. Do not add diagnostic workflow machinery.

---

## Completion criteria

PR 1 is implementation-complete only when all of these are true:

1. `p3-project.el` exclusively owns `p3/project-root` and `p3/use-project-root-as-default-dir`.
2. No P3 implementation calls `projectile-project-root` or the retired `p3/project-el-root` helper.
3. ESS, R tools, Python, and terminal code consume the same `p3/project-root` contract.
4. Existing `.projectile` projects are recognized by native `project.el`, including nested projects inside outer Git repositories.
5. Python resolves `.venv` from that shared inner root in the nested-project case.
6. `config.org` eagerly loads `p3-project` after Windows Unix-tool path setup and before project-aware P3 modules.
7. Existing R project scaffolding still creates `.projectile`, with explicit ERT coverage.
8. The one-/two-window workflow is unchanged.
9. Linux byte-compilation and the complete ERT suite pass.
10. Native Windows project detection and `project-files` enumeration pass through the existing platform path setup.
11. The final diff contains no Projectile removal, ESS redesign, Python environment-manager redesign, Org changes, startup/tangling redesign, or buffer-layout changes.
12. The branch is not merged without explicit user approval.
