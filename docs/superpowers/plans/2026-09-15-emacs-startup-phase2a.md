# Emacs Startup Phase 2A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add lightweight, repeatable startup instrumentation and capture the pre-optimization Phase 2 baseline without intentionally changing startup loading behavior.

**Architecture:** Load a dependency-free `p3-startup-profile` module at the beginning of `init.el`, record named elapsed-time phases only while startup is active, and aggregate repeated boundaries such as `use-package` ensure calls. Reuse `p3/config-load-module` and `p3/config-load` as instrumentation boundaries; compiled loading, Org-roam deferral, and all other lazy-loading work remain Phase 2B.

**Tech Stack:** Emacs Lisp, built-in timing APIs, ERT, GitHub Actions on Linux and native Windows.

**Spec:** `docs/superpowers/specs/2026-09-15-emacs-startup-phase2-design.md`

## Global Constraints

- Phase 2A is diagnostics-only: no intentional module deferral, package-activation change, or loader-semantics change.
- Preserve exact-source development reload behavior.
- Use normal Emacs mechanisms only; add no module registry, performance cache, or timing threshold.
- Linux and native Windows remain behaviorally equivalent.
- Phase 2B does not begin until the Phase 2A baseline has been recorded where practical.

---

### Task 1: Add the startup profiling core

**Files:**
- Create: `lisp/p3-startup-profile.el`
- Create: `test/p3-startup-profile-test.el`

**Interfaces:**
- Produces `p3/startup-profile-active`, `p3/startup-profile-phases`, `p3/startup-profile-total-seconds`, `p3/startup-profile-record`, `p3/with-startup-profile-phase`, `p3/startup-profile-finish`, `p3/startup-profile-format`, and `p3/startup-profile-report`.
- Phase records are `(NAME SECONDS COUNT)` in first-seen order; repeated names accumulate elapsed seconds and increment `COUNT`.

- [ ] **Step 1: Write failing ERT coverage**

Create `test/p3-startup-profile-test.el` with deterministic tests for aggregation, inactive-wrapper behavior, startup completion, and report formatting:

```elisp
(require 'ert)
(require 'cl-lib)

(defconst p3-startup-profile-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))
(add-to-list 'load-path (expand-file-name "lisp" p3-startup-profile-test--root))
(require 'p3-startup-profile)

(ert-deftest p3-startup-profile-records-and-aggregates ()
  (let ((p3/startup-profile-active t)
        (p3/startup-profile-phases nil))
    (p3/startup-profile-record "ensure" 0.10)
    (p3/startup-profile-record "other" 0.20)
    (p3/startup-profile-record "ensure" 0.30)
    (should (equal p3/startup-profile-phases
                   '(("ensure" 0.40 2) ("other" 0.20 1))))))

(ert-deftest p3-startup-profile-wrapper-skips-clock-after-startup ()
  (let ((p3/startup-profile-active nil)
        called)
    (cl-letf (((symbol-function 'float-time)
               (lambda (&optional _time) (setq called t) 0.0)))
      (should (eq (p3/with-startup-profile-phase "inactive" 'ok) 'ok)))
    (should-not called)))

(ert-deftest p3-startup-profile-finish-freezes-total ()
  (let ((p3/startup-profile-active t)
        (p3/startup-profile-total-seconds nil)
        (before-init-time (seconds-to-time 100.0)))
    (cl-letf (((symbol-function 'current-time)
               (lambda () (seconds-to-time 102.5))))
      (p3/startup-profile-finish))
    (should (= p3/startup-profile-total-seconds 2.5))
    (should-not p3/startup-profile-active)))

(ert-deftest p3-startup-profile-format-is-shareable ()
  (let ((p3/startup-profile-total-seconds 1.5)
        (p3/startup-profile-phases
         '(("package-initialize" 0.2 1)
           ("use-package-ensure" 0.3 4))))
    (let ((text (p3/startup-profile-format)))
      (should (string-match-p (regexp-quote emacs-version) text))
      (should (string-match-p (regexp-quote (symbol-name system-type)) text))
      (should (string-match-p "Total init: 1\\.500 s" text))
      (should (string-match-p "use-package-ensure.*4 calls" text)))))
```

- [ ] **Step 2: Run the focused test and verify RED**

```bash
emacs -Q --batch -L lisp -l test/p3-startup-profile-test.el -f ert-run-tests-batch-and-exit
```

Expected: failure because `p3-startup-profile` does not exist.

- [ ] **Step 3: Implement the minimal profiler**

Create `lisp/p3-startup-profile.el` with normal file commentary/docstrings and this behavior:

```elisp
(defvar p3/startup-profile-active t)
(defvar p3/startup-profile-phases nil)
(defvar p3/startup-profile-total-seconds nil)

(defun p3/startup-profile-record (name seconds)
  (when p3/startup-profile-active
    (let ((entry (assoc-string name p3/startup-profile-phases t)))
      (if entry
          (setf (nth 1 entry) (+ (nth 1 entry) seconds)
                (nth 2 entry) (1+ (nth 2 entry)))
        (setq p3/startup-profile-phases
              (append p3/startup-profile-phases
                      (list (list name seconds 1)))))))
  seconds)

(defmacro p3/with-startup-profile-phase (name &rest body)
  (declare (indent 1) (debug t))
  `(if p3/startup-profile-active
       (let ((p3-startup-profile--started (float-time)))
         (prog1 (progn ,@body)
           (p3/startup-profile-record
            ,name (- (float-time) p3-startup-profile--started))))
     (progn ,@body)))

(defun p3/startup-profile-finish ()
  (when p3/startup-profile-active
    (setq p3/startup-profile-total-seconds
          (float-time (time-subtract (current-time) before-init-time))
          p3/startup-profile-active nil)))

(defun p3/startup-profile-format ()
  (with-temp-buffer
    (insert "P3 startup profile\n"
            (format "Platform: %s\n" system-type)
            (format "Emacs: %s\n" emacs-version)
            (if p3/startup-profile-total-seconds
                (format "Total init: %.3f s\n" p3/startup-profile-total-seconds)
              "Total init: startup still active\n")
            "\nPhases:\n")
    (dolist (entry p3/startup-profile-phases)
      (insert (format "%-32s %8.3f s%s\n"
                      (nth 0 entry) (nth 1 entry)
                      (if (> (nth 2 entry) 1)
                          (format "  (%d calls)" (nth 2 entry)) ""))))
    (buffer-string)))

;;;###autoload
(defun p3/startup-profile-report ()
  (interactive)
  (let ((buffer (get-buffer-create "*P3 Startup Profile*")))
    (with-current-buffer buffer
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (p3/startup-profile-format))
        (goto-char (point-min))
        (special-mode)))
    (display-buffer buffer)))

(add-hook 'emacs-startup-hook #'p3/startup-profile-finish)
(provide 'p3-startup-profile)
```

- [ ] **Step 4: Verify GREEN and strict byte compilation**

```bash
emacs -Q --batch -L lisp -l test/p3-startup-profile-test.el -f ert-run-tests-batch-and-exit
emacs -Q --batch -L lisp --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile lisp/p3-startup-profile.el
```

Expected: both commands succeed.

- [ ] **Step 5: Commit**

```bash
git add lisp/p3-startup-profile.el test/p3-startup-profile-test.el
git commit -m "feat: add startup profiling core"
```

### Task 2: Instrument existing startup boundaries without changing semantics

**Files:**
- Modify: `init.el`
- Modify: `lisp/p3-config-loader.el`
- Modify: `test/p3-startup-profile-test.el`
- Modify: `test/p3-config-loader-test.el`

**Interfaces:**
- Adds stable names `package-initialize`, `use-package-bootstrap`, `use-package-ensure`, `config-cache-validate`, `config-cache-build`, `config-cache-load`, and `module:<feature>`.
- `p3/config-load-module` remains exact-source `load-file` in Phase 2A.

- [ ] **Step 1: Add failing loader-phase tests**

Append to `test/p3-config-loader-test.el`:

```elisp
(ert-deftest p3-config-loader-profiles-local-module-during-startup ()
  (let* ((directory (make-temp-file "p3-profiled-module-" t))
         (p3/config-lisp-directory directory)
         (source (expand-file-name "p3-profiled-module.el" directory))
         (p3/startup-profile-active t)
         (p3/startup-profile-phases nil))
    (unwind-protect
        (progn
          (with-temp-file source (insert "(provide 'p3-profiled-module)\n"))
          (p3/config-load-module 'p3-profiled-module)
          (should (assoc-string "module:p3-profiled-module"
                                p3/startup-profile-phases)))
      (setq features (delq 'p3-profiled-module features))
      (delete-directory directory t))))

(ert-deftest p3-config-loader-profiles-current-cache-validation-and-load ()
  (let ((p3/startup-profile-active t)
        (p3/startup-profile-phases nil))
    (cl-letf (((symbol-function 'p3/config-cache-stale-p) (lambda () nil))
              ((symbol-function 'p3/config-load-generated) (lambda () 'loaded)))
      (should (eq (p3/config-load) 'loaded)))
    (should (assoc-string "config-cache-validate" p3/startup-profile-phases))
    (should (assoc-string "config-cache-load" p3/startup-profile-phases))
    (should-not (assoc-string "config-cache-build" p3/startup-profile-phases))))

(ert-deftest p3-config-loader-profiles-cache-build-only-when-stale ()
  (let ((p3/startup-profile-active t)
        (p3/startup-profile-phases nil)
        built)
    (cl-letf (((symbol-function 'p3/config-cache-stale-p) (lambda () t))
              ((symbol-function 'p3/config-build) (lambda () (setq built t)))
              ((symbol-function 'p3/config-load-generated) (lambda () 'loaded)))
      (p3/config-load))
    (should built)
    (should (assoc-string "config-cache-build" p3/startup-profile-phases))))
```

Append to `test/p3-startup-profile-test.el` a source-contract test that reads `init.el`, returns to `point-min`, and `search-forward`s for all three exact strings:

```elisp
p3/with-startup-profile-phase "package-initialize"
p3/with-startup-profile-phase "use-package-bootstrap"
p3/with-startup-profile-phase "use-package-ensure"
```

The source-contract test is intentional because loading the real `init.el` in CI would permit network-dependent package bootstrap.

- [ ] **Step 2: Run focused tests and verify RED**

```bash
emacs -Q --batch -L lisp -l test/p3-startup-profile-test.el -l test/p3-config-loader-test.el -f ert-run-tests-batch-and-exit
```

- [ ] **Step 3: Load profiling before package setup**

In `init.el`, move the existing `p3/lisp-directory` definition and `load-path` addition immediately after `custom-file`, add:

```elisp
(require 'p3-startup-profile)
```

and remove the later duplicate `p3/lisp-directory` block. Move no other startup behavior.

- [ ] **Step 4: Instrument package boundaries**

Use:

```elisp
(p3/with-startup-profile-phase "package-initialize"
  (package-initialize))

(p3/with-startup-profile-phase "use-package-bootstrap"
  (p3/package-install-resilient 'use-package)
  (require 'use-package)
  (require 'use-package-ensure))
```

Wrap the existing `p3/use-package-ensure` body without changing its package logic:

```elisp
(defun p3/use-package-ensure (name args _state)
  "Ensure packages requested by use-package NAME with normalized ARGS."
  (p3/with-startup-profile-phase "use-package-ensure"
    (dolist (ensure args)
      (let ((package (if (eq ensure t)
                         (use-package-as-symbol name)
                       ensure)))
        (when package
          (when (consp package)
            (use-package-pin-package (car package) (cdr package))
            (setq package (car package)))
          (condition-case err
              (p3/package-install-resilient package)
            (error
             (display-warning
              'use-package
              (format "Failed to install %s: %s"
                      package (error-message-string err))
              :error)))))))
  t)
```

- [ ] **Step 5: Instrument config-cache and local-module boundaries**

In `lisp/p3-config-loader.el`, require `p3-startup-profile`, wrap the existing exact-source load:

```elisp
(p3/with-startup-profile-phase (format "module:%s" module)
  (load-file path))
```

and replace `p3/config-load` with:

```elisp
(defun p3/config-load ()
  "Load the config cache, rebuilding first when it is stale."
  (let ((stale
         (p3/with-startup-profile-phase "config-cache-validate"
           (p3/config-cache-stale-p))))
    (when stale
      (p3/with-startup-profile-phase "config-cache-build"
        (p3/config-build)))
    (p3/with-startup-profile-phase "config-cache-load"
      (p3/config-load-generated))))
```

- [ ] **Step 6: Verify GREEN and preserve exact-source behavior**

```bash
emacs -Q --batch -L lisp -l test/p3-startup-profile-test.el -l test/p3-config-loader-test.el -f ert-run-tests-batch-and-exit
emacs -Q --batch -L lisp --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile lisp/p3-startup-profile.el lisp/p3-config-loader.el
```

Expected: success, including the existing `p3-config-loader-load-module-reloads-exact-source` regression.

- [ ] **Step 7: Commit**

```bash
git add init.el lisp/p3-config-loader.el test/p3-startup-profile-test.el test/p3-config-loader-test.el
git commit -m "perf: instrument startup boundaries"
```

### Task 3: Add cross-platform ownership and capture the Phase 2A baseline

**Files:**
- Modify: `.github/workflows/emacs-tests.yml`
- Modify: `.github/workflows/windows-platform-tests.yml`
- Create: `docs/startup-performance.md`
- Update: Phase 2A PR description and/or issue #80 with measured evidence.

**Interfaces:**
- Linux and Windows byte-compile and execute the diagnostic tests.
- Human measurements use only `M-x p3/startup-profile-report`; hosted CI has no timing threshold.

- [ ] **Step 1: Add Linux CI coverage**

In `.github/workflows/emacs-tests.yml`, add `lisp/p3-startup-profile.el` immediately before `lisp/p3-config-loader.el` in byte compilation and `-l test/p3-startup-profile-test.el` immediately before `-l test/p3-config-loader-test.el` in the ERT suite.

- [ ] **Step 2: Add native-Windows CI coverage**

In `.github/workflows/windows-platform-tests.yml`:

- add `init.el`, `lisp/p3-startup-profile.el`, and `test/p3-startup-profile-test.el` to the pull-request `paths` list;
- add `lisp/p3-startup-profile.el` immediately before `lisp/p3-config-loader.el` in warning-as-error byte compilation;
- add `-l test/p3-startup-profile-test.el` immediately before `-l test/p3-config-loader-test.el` in `Run Windows config architecture tests`.

- [ ] **Step 3: Create the canonical measurement procedure**

Create `docs/startup-performance.md` with:

```markdown
# Emacs startup performance measurement

Use this procedure for issue #80 Phase 2 before/after comparisons.

1. Use a normal machine state with required Emacs packages already installed.
2. Start Emacs normally; do not use `p3/config-reload` as a substitute for a fresh process.
3. After startup completes, run `M-x p3/startup-profile-report` and copy the entire report.
4. Exit Emacs completely and repeat until three reports are captured.
5. Capture three fresh-process reports on GNU/Linux and three on native Windows where practical.
6. Retain every sample; note a suspected cold-filesystem outlier rather than silently dropping it.

Compare `Total init`, `package-initialize`, `use-package-bootstrap`, aggregate `use-package-ensure`, config-cache phases, and material `module:*` phases. A current-cache startup normally has no `config-cache-build` phase.

Paste the raw reports or a faithful table into the implementing PR and/or issue #80. Repeat the identical procedure after Phase 2B. CI verifies structural behavior only and must not enforce startup-time thresholds.
```

- [ ] **Step 4: Run focused and platform suites**

Always run:

```bash
emacs -Q --batch -L lisp -l test/p3-startup-profile-test.el -l test/p3-config-loader-test.el -f ert-run-tests-batch-and-exit
```

Then run the repository's normal Linux ERT command on Linux or `Run Windows config architecture tests` on native Windows. Expected: zero unexpected failures.

- [ ] **Step 5: Commit CI/docs**

```bash
git add .github/workflows/emacs-tests.yml .github/workflows/windows-platform-tests.yml docs/startup-performance.md
git commit -m "test: cover startup profiling across platforms"
```

- [ ] **Step 6: Open a draft Phase 2A PR and collect baseline evidence**

Use title `Instrument Emacs startup for Phase 2 performance work`. State explicitly that it is diagnostics-only. On each available workstation platform, perform three fresh starts using `docs/startup-performance.md` and add the raw reports or faithful phase tables to the PR or issue #80. If one workstation platform is unavailable, record that fact rather than substituting hosted-runner wall-clock values.

- [ ] **Step 7: Final review and verification**

Verify from the diff:

```text
p3/config-load-module still uses exact tracked source via load-file.
config.org module order is unchanged.
No :defer, autoload, idle timer, Org-roam, or compiled-loader behavior change is present.
p3/package-install-resilient semantics are unchanged.
p3/use-package-ensure differs only by the timing wrapper.
Profiling stops at emacs-startup-hook.
```

Mark the PR ready, require fresh Linux and native-Windows CI success, and merge Phase 2A separately from Phase 2B.
