# Startup/Tangle Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace unconditional startup tangling with a content-validated local `config.el` cache that rebuilds only when `config.org` changes.

**Architecture:** Add `lisp/p3-config-loader.el` as the sole owner of config fingerprinting, staged tangling, validation, replacement, and loading. `init.el` keeps bootstrap ordering and calls the loader; `p3-core.el` keeps user-facing visit/reload commands. Cache validity is an embedded SHA-256 of the exact `config.org` bytes, not filesystem timestamps.

**Tech Stack:** Emacs Lisp 29+, Org/Babel, ERT, package.el/use-package bootstrap, GitHub Actions on Ubuntu and native Windows.

**Spec:** `docs/superpowers/specs/2026-09-03-startup-tangle-cache-design.md`

## Global Constraints

- `config.org` remains the only authoritative configuration source.
- `config.el` remains ignored by Git and is never treated as source.
- Cache validity uses an embedded SHA-256 of the exact current `config.org` contents; modification times do not participate.
- The current-cache startup path must not require Org or Babel through the loader.
- Builds tangle only `emacs-lisp` blocks into one staged same-directory file.
- Existing alternate `:tangle` behavior is not supported; any effective `:tangle` value other than the normal disabled value (`no`) is rejected before tangling so it cannot bypass staging.
- A staged file replaces `config.el` only after tangle output, source fingerprint, and Lisp syntax are validated.
- Replacement uses one same-directory `rename-file` with overwrite enabled; never delete `config.el` first.
- `p3/config-load-generated` uses `load-file` on the exact `.el` cache; no `.elc` selection.
- Tangle/validation failures preserve the running session and previous cache; runtime load failures are not transactional and are allowed to leave partial session effects.
- `p3-project` must still load before the literate configuration.
- Existing config visit/reload keybindings remain unchanged.
- Do not reorganize `config.org`, redesign package bootstrap, change project semantics, or alter completion/ESS/Python/Org/terminal/window behavior.
- Extend existing CI only; do not add a new workflow, matrix, cache service, or diagnostic harness.
- Keep GitHub Actions use bounded: establish red/green with targeted local batch commands when an Emacs runtime is available, then use the existing remote workflows as the final branch gate rather than as an iterative debugger.

---

## File Structure

- **Create `lisp/p3-config-loader.el`** — config source/cache paths, SHA-256 fingerprint handling, tangle-contract validation, staged build, exact generated-file load, startup load decision.
- **Create `test/p3-config-loader-test.el`** — isolated unit tests for fingerprinting, direct loading, stale-cache rebuilds, staged build behavior, failure preservation, and replacement.
- **Modify `lisp/p3-core.el`** — depend on the loader and implement reload as exactly one explicit build plus one direct load.
- **Modify `init.el`** — remove unconditional Org/Babel/tangle bootstrap and call `p3/config-load` after `p3-project`.
- **Modify `test/p3-core-test.el`** — verify reload delegates exactly once to build and direct load.
- **Modify `test/p3-config-test.el`** — update bootstrap-order assertions and run the real `config.org` through the loader build contract.
- **Modify `.github/workflows/emacs-tests.yml`** — byte-compile the loader and load loader tests before tests that require Org.
- **Modify `.github/workflows/windows-platform-tests.yml`** — include loader paths, byte-compile the loader, and run one focused replacement-path ERT test natively on Windows.

---

### Task 1: Content Fingerprinting and Exact Cache Loading

**Files:**
- Create: `lisp/p3-config-loader.el`
- Create: `test/p3-config-loader-test.el`

**Interfaces:**
- Produces: `p3/config-source` — absolute path to `config.org`.
- Produces: `p3/config-generated` — absolute path to ignored `config.el`.
- Produces: `p3/config-cache-stale-p` — returns non-nil unless the generated header fingerprint exactly matches the current source digest.
- Produces: `p3/config-load-generated` — loads exactly `p3/config-generated` with `load-file`.
- Produces: `p3/config-load` — later uses `p3/config-build` on stale/missing cache, then loads the exact generated file.
- Internal: `p3/config--source-digest`, `p3/config--generated-digest`, `p3/config--fingerprint-prefix`.

- [ ] **Step 1: Write the loader tests for content-based validity**

Create `test/p3-config-loader-test.el` with a loader-isolation snapshot taken immediately after requiring the new module, before this test file itself loads Org:

```elisp
;;; p3-config-loader-test.el --- Tests for config cache loading -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)

(defconst p3-config-loader-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-config-loader-test--root))
(require 'p3-config-loader)

(defconst p3-config-loader-test--org-loaded-by-loader-p (featurep 'org))
(defconst p3-config-loader-test--ob-tangle-loaded-by-loader-p (featurep 'ob-tangle))

(defun p3-config-loader-test--digest (path)
  "Return the SHA-256 digest of PATH's exact bytes."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally path)
    (secure-hash 'sha256 (current-buffer))))

(defmacro p3-config-loader-test--with-files (source-content &rest body)
  "Run BODY with temporary config source/cache files."
  (declare (indent 1))
  `(let* ((directory (make-temp-file "p3-config-loader-test-" t))
          (p3/config-source (expand-file-name "config.org" directory))
          (p3/config-generated (expand-file-name "config.el" directory)))
     (unwind-protect
         (progn
           (with-temp-file p3/config-source
             (insert ,source-content))
           ,@body)
       (delete-directory directory t))))

(defun p3-config-loader-test--write-current-cache (body)
  "Write BODY to the current temporary cache with a matching fingerprint."
  (let ((digest (p3-config-loader-test--digest p3/config-source)))
    (with-temp-file p3/config-generated
      (insert ";; p3-config-source-sha256: " digest "\n" body))))

(ert-deftest p3-config-loader-does-not-load-org-at-module-load ()
  (should-not p3-config-loader-test--org-loaded-by-loader-p)
  (should-not p3-config-loader-test--ob-tangle-loaded-by-loader-p))

(ert-deftest p3-config-loader-missing-cache-is-stale ()
  (p3-config-loader-test--with-files "source"
    (should (p3/config-cache-stale-p))))

(ert-deftest p3-config-loader-malformed-fingerprint-is-stale ()
  (p3-config-loader-test--with-files "source"
    (with-temp-file p3/config-generated
      (insert ";; p3-config-source-sha256: not-a-digest\n"))
    (should (p3/config-cache-stale-p))))

(ert-deftest p3-config-loader-mismatched-fingerprint-is-stale-regardless-of-mtime ()
  (p3-config-loader-test--with-files "source-v1"
    (p3-config-loader-test--write-current-cache "(setq p3-test-cache t)\n")
    (with-temp-file p3/config-source
      (insert "source-v2"))
    (set-file-times p3/config-source (seconds-to-time 1000000000))
    (set-file-times p3/config-generated (seconds-to-time 2000000000))
    (should (p3/config-cache-stale-p))))

(ert-deftest p3-config-loader-matching-fingerprint-is-current-regardless-of-mtime ()
  (p3-config-loader-test--with-files "source"
    (p3-config-loader-test--write-current-cache "(setq p3-test-cache t)\n")
    (set-file-times p3/config-generated (seconds-to-time 1000000000))
    (set-file-times p3/config-source (seconds-to-time 2000000000))
    (should-not (p3/config-cache-stale-p))))
```

- [ ] **Step 2: Run the new tests and verify the missing module fails red**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-loader-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: FAIL while loading `p3-config-loader` because `lisp/p3-config-loader.el` does not yet exist.

- [ ] **Step 3: Implement the minimal fingerprint reader and stale predicate**

Create `lisp/p3-config-loader.el` with no top-level Org/Babel dependency:

```elisp
;;; p3-config-loader.el --- Build and load the literate config cache -*- lexical-binding: t; -*-

(defconst p3/config-source
  (expand-file-name "config.org" user-emacs-directory)
  "Authoritative literate Emacs configuration.")

(defconst p3/config-generated
  (expand-file-name "config.el" user-emacs-directory)
  "Ignored generated cache for `p3/config-source'.")

(defconst p3/config--fingerprint-prefix
  ";; p3-config-source-sha256: "
  "Prefix used to record the source digest in the generated cache.")

(defun p3/config--source-digest ()
  "Return the SHA-256 digest of the exact bytes in `p3/config-source'."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally p3/config-source)
    (secure-hash 'sha256 (current-buffer))))

(defun p3/config--generated-digest ()
  "Return the recorded source digest from `p3/config-generated', or nil."
  (when (file-readable-p p3/config-generated)
    (with-temp-buffer
      (insert-file-contents p3/config-generated nil 0 160)
      (goto-char (point-min))
      (when (looking-at
             (concat (regexp-quote p3/config--fingerprint-prefix)
                     "\\([0-9a-f]\\{64\\}\\)$"))
        (match-string-no-properties 1)))))

(defun p3/config-cache-stale-p ()
  "Return non-nil unless the generated cache matches the current source."
  (let ((recorded (p3/config--generated-digest)))
    (or (null recorded)
        (not (equal recorded (p3/config--source-digest))))))

(provide 'p3-config-loader)

;;; p3-config-loader.el ends here
```

- [ ] **Step 4: Run the fingerprint tests and verify green**

Run the same targeted batch command.

Expected: all fingerprint/isolation tests PASS.

- [ ] **Step 5: Add tests for exact `.el` loading and the current-cache path**

Append:

```elisp
(ert-deftest p3-config-loader-load-generated-uses-exact-el-file ()
  (p3-config-loader-test--with-files "source"
    (p3-config-loader-test--write-current-cache
     "(setq p3-config-loader-test--loaded 'source)\n")
    (with-temp-file (concat p3/config-generated "c")
      (insert "(setq p3-config-loader-test--loaded 'compiled)\n"))
    (setq p3-config-loader-test--loaded nil)
    (p3/config-load-generated)
    (should (eq p3-config-loader-test--loaded 'source))))

(ert-deftest p3-config-loader-current-cache-loads-without-build-or-org-require ()
  (p3-config-loader-test--with-files "source"
    (p3-config-loader-test--write-current-cache
     "(setq p3-config-loader-test--loaded 'current)\n")
    (setq p3-config-loader-test--loaded nil)
    (let ((original-require (symbol-function 'require)))
      (cl-letf (((symbol-function 'p3/config-build)
                 (lambda () (ert-fail "Current cache attempted a rebuild")))
                ((symbol-function 'require)
                 (lambda (feature &rest args)
                   (when (memq feature '(org ob-tangle))
                     (ert-fail (format "Current cache required %S" feature)))
                   (apply original-require feature args))))
        (p3/config-load)))
    (should (eq p3-config-loader-test--loaded 'current))))
```

- [ ] **Step 6: Run the tests and verify the new functions fail red**

Expected: FAIL because `p3/config-load-generated` / `p3/config-load` are undefined.

- [ ] **Step 7: Implement exact loading and the startup entry point**

Add:

```elisp
(defun p3/config-load-generated ()
  "Load exactly the generated Emacs Lisp cache."
  (load-file p3/config-generated))

(defun p3/config-load ()
  "Load the config cache, rebuilding first when it is stale."
  (when (p3/config-cache-stale-p)
    (p3/config-build))
  (p3/config-load-generated))
```

Do not implement a fake `p3/config-build`; Task 2 immediately supplies the build implementation. For this Task 1 green run, the current-cache test binds `p3/config-build` and therefore never calls the undefined production function.

- [ ] **Step 8: Run only the Task 1 tests and verify green**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-loader-test.el \
  --eval '(ert-run-tests-batch-and-exit "^p3-config-loader-\\(does-not-load-org\\|missing-cache\\|malformed-fingerprint\\|mismatched-fingerprint\\|matching-fingerprint\\|load-generated\\|current-cache\\)")'
```

Expected: PASS.

- [ ] **Step 9: Commit Task 1**

```bash
git add lisp/p3-config-loader.el test/p3-config-loader-test.el
git commit -m "feat: add content-validated config cache loading"
```

---

### Task 2: Guarded Staged Tangling and Atomic Cache Replacement

**Files:**
- Modify: `lisp/p3-config-loader.el`
- Modify: `test/p3-config-loader-test.el`

**Interfaces:**
- Consumes: Task 1's source/generated paths and fingerprint helpers.
- Produces: interactive `p3/config-build`, returning `p3/config-generated` after successful replacement.
- Internal: `p3/config--validate-tangle-contract`, `p3/config--assert-readable-elisp`, `p3/config--insert-fingerprint`, `p3/config--assert-single-tangle-output`.

- [ ] **Step 1: Add Org only after capturing module-load isolation**

Immediately after the two `p3-config-loader-test--*-loaded-by-loader-p` constants in the test file, add:

```elisp
(require 'org)
(require 'ob-tangle)
```

This lets build tests use real Babel while preserving the earlier evidence that loading `p3-config-loader` itself did not load Org/Babel.

- [ ] **Step 2: Write red tests for the tangle boundary and language filter**

Add:

```elisp
(defun p3-config-loader-test--stage-files (directory)
  "Return staged config-cache files remaining in DIRECTORY."
  (directory-files directory t "\\`\\.p3-config-stage-"))

(ert-deftest p3-config-loader-rejects-explicit-tangle-before-writing ()
  (p3-config-loader-test--with-files
      "#+PROPERTY: header-args:emacs-lisp :tangle escaped.el\n#+begin_src emacs-lisp\n(setq p3-test t)\n#+end_src\n"
    (let ((escaped (expand-file-name "escaped.el" (file-name-directory p3/config-source))))
      (should-error (p3/config-build))
      (should-not (file-exists-p escaped))
      (should-not (file-exists-p p3/config-generated)))))

(ert-deftest p3-config-loader-build-admits-only-emacs-lisp ()
  (p3-config-loader-test--with-files
      "#+begin_src emacs-lisp\n(setq p3-config-loader-test--language 'elisp)\n#+end_src\n#+begin_src shell\necho SHOULD_NOT_APPEAR\n#+end_src\n"
    (p3/config-build)
    (with-temp-buffer
      (insert-file-contents p3/config-generated)
      (should (search-forward "p3-config-loader-test--language" nil t))
      (goto-char (point-min))
      (should-not (search-forward "SHOULD_NOT_APPEAR" nil t)))))
```

Run the loader suite. Expected: FAIL because `p3/config-build` is undefined.

- [ ] **Step 3: Add declarations and tangle-contract validation without a top-level Org require**

Add near the top of `p3-config-loader.el`:

```elisp
(declare-function org-mode "org" ())
(declare-function org-babel-next-src-block "ob-core" (&optional arg))
(declare-function org-babel-get-src-block-info "ob-core" (&optional light datum))
(declare-function org-babel-tangle-file "ob-tangle" (file &optional target-file lang-re))
```

Add:

```elisp
(defun p3/config--validate-tangle-contract ()
  "Reject source blocks whose existing tangle setting could escape staging."
  (with-temp-buffer
    (insert-file-contents p3/config-source)
    (setq buffer-file-name p3/config-source)
    (org-mode)
    (goto-char (point-min))
    (while (org-babel-next-src-block 1)
      (let* ((info (org-babel-get-src-block-info 'light))
             (params (nth 2 info))
             (tangle (cdr (assq :tangle params))))
        (unless (or (null tangle) (equal (format "%s" tangle) "no"))
          (user-error "Unsupported :tangle setting %S in %s"
                      tangle p3/config-source))))))
```

Reject `yes` as well as filenames: either can override the staged target supplied by the loader.

- [ ] **Step 4: Write red tests for output validation, syntax preservation, source stability, and cleanup**

Add:

```elisp
(ert-deftest p3-config-loader-tangle-failure-preserves-cache-and-cleans-stage ()
  (p3-config-loader-test--with-files
      "#+begin_src emacs-lisp\n(setq p3-test t)\n#+end_src\n"
    (with-temp-file p3/config-generated
      (insert "old-cache"))
    (let ((directory (file-name-directory p3/config-generated)))
      (cl-letf (((symbol-function 'org-babel-tangle-file)
                 (lambda (&rest _) (error "synthetic tangle failure"))))
        (should-error (p3/config-build)))
      (should (equal (with-temp-buffer
                       (insert-file-contents p3/config-generated)
                       (buffer-string))
                     "old-cache"))
      (should-not (p3-config-loader-test--stage-files directory)))))

(ert-deftest p3-config-loader-malformed-output-preserves-cache ()
  (p3-config-loader-test--with-files
      "#+begin_src emacs-lisp\n(setq p3-test t)\n#+end_src\n"
    (with-temp-file p3/config-generated
      (insert "old-cache"))
    (cl-letf (((symbol-function 'org-babel-tangle-file)
               (lambda (_source target _language)
                 (with-temp-file target (insert "(unclosed"))
                 (list target))))
      (should-error (p3/config-build)))
    (should (equal (with-temp-buffer
                     (insert-file-contents p3/config-generated)
                     (buffer-string))
                   "old-cache"))))

(ert-deftest p3-config-loader-rejects-unexpected-tangle-output ()
  (p3-config-loader-test--with-files
      "#+begin_src emacs-lisp\n(setq p3-test t)\n#+end_src\n"
    (with-temp-file p3/config-generated
      (insert "old-cache"))
    (cl-letf (((symbol-function 'org-babel-tangle-file)
               (lambda (_source target _language)
                 (with-temp-file target (insert "(setq p3-test t)\n"))
                 (list target (expand-file-name "unexpected.el"
                                                (file-name-directory target)))))))
      (should-error (p3/config-build)))
    (should (equal (with-temp-buffer
                     (insert-file-contents p3/config-generated)
                     (buffer-string))
                   "old-cache"))))

(ert-deftest p3-config-loader-source-change-during-build-preserves-cache ()
  (p3-config-loader-test--with-files
      "#+begin_src emacs-lisp\n(setq p3-test 'old)\n#+end_src\n"
    (with-temp-file p3/config-generated
      (insert "old-cache"))
    (cl-letf (((symbol-function 'org-babel-tangle-file)
               (lambda (_source target _language)
                 (with-temp-file target (insert "(setq p3-test 'old)\n"))
                 (with-temp-file p3/config-source
                   (insert "#+begin_src emacs-lisp\n(setq p3-test 'new)\n#+end_src\n"))
                 (list target))))
      (should-error (p3/config-build)))
    (should (equal (with-temp-buffer
                     (insert-file-contents p3/config-generated)
                     (buffer-string))
                   "old-cache"))))
```

The source-stability test closes the narrow race between hashing and tangling: the fingerprint published in `config.el` must describe the same source contents that were actually tangled.

- [ ] **Step 5: Implement staged-file validation helpers**

Add:

```elisp
(defun p3/config--assert-single-tangle-output (outputs staged)
  "Require OUTPUTS to contain only STAGED."
  (unless (and (= (length outputs) 1)
               (file-equal-p (car outputs) staged))
    (error "Config tangle produced unexpected outputs: %S" outputs)))

(defun p3/config--insert-fingerprint (path digest)
  "Insert DIGEST as the generated-cache fingerprint at the start of PATH."
  (with-temp-buffer
    (insert-file-contents path)
    (goto-char (point-min))
    (insert p3/config--fingerprint-prefix digest "\n")
    (write-region (point-min) (point-max) path nil 'silent)))

(defun p3/config--assert-readable-elisp (path)
  "Signal an error unless PATH contains syntactically readable Emacs Lisp."
  (with-temp-buffer
    (insert-file-contents path)
    (emacs-lisp-mode)
    (check-parens)
    (goto-char (point-min))
    (condition-case nil
        (while t
          (read (current-buffer)))
      (end-of-file t))))
```

- [ ] **Step 6: Implement `p3/config-build` with one guarded replacement**

Add:

```elisp
(defun p3/config-build ()
  "Rebuild and validate the generated cache from `p3/config-source'."
  (interactive)
  (let* ((source-digest (p3/config--source-digest))
         (directory (file-name-directory p3/config-generated))
         (staged (make-temp-file
                  (expand-file-name ".p3-config-stage-" directory)
                  nil ".el")))
    (unwind-protect
        (progn
          (require 'org)
          (require 'ob-tangle)
          (p3/config--validate-tangle-contract)
          (let ((outputs
                 (org-babel-tangle-file
                  p3/config-source staged "emacs-lisp")))
            (p3/config--assert-single-tangle-output outputs staged))
          (unless (equal source-digest (p3/config--source-digest))
            (error "%s changed while the config cache was being built"
                   p3/config-source))
          (p3/config--insert-fingerprint staged source-digest)
          (p3/config--assert-readable-elisp staged)
          (rename-file staged p3/config-generated t)
          (when (called-interactively-p 'interactive)
            (message "Built %s" p3/config-generated))
          p3/config-generated)
      (when (file-exists-p staged)
        (delete-file staged)))))
```

Do not catch build errors. The caller must see tangle/validation failures, and stale startup must not silently load the older cache.

- [ ] **Step 7: Add green tests for replacement, stale startup rebuilding, and explicit rebuilding**

Add:

```elisp
(ert-deftest p3-config-loader-build-replaces-existing-cache ()
  (p3-config-loader-test--with-files
      "#+begin_src emacs-lisp\n(setq p3-config-loader-test--replacement 'new)\n#+end_src\n"
    (with-temp-file p3/config-generated
      (insert "old-cache"))
    (let ((directory (file-name-directory p3/config-generated)))
      (should (equal (p3/config-build) p3/config-generated))
      (should (commandp #'p3/config-build))
      (should-not (p3/config-cache-stale-p))
      (with-temp-buffer
        (insert-file-contents p3/config-generated)
        (goto-char (point-min))
        (should (looking-at ";; p3-config-source-sha256: [0-9a-f]\\{64\\}$"))
        (should (search-forward "p3-config-loader-test--replacement" nil t)))
      (should-not (p3-config-loader-test--stage-files directory)))))

(ert-deftest p3-config-loader-mismatched-cache-rebuilds-before-load ()
  (p3-config-loader-test--with-files
      "#+begin_src emacs-lisp\n(setq p3-config-loader-test--loaded 'fresh)\n#+end_src\n"
    (with-temp-file p3/config-generated
      (insert ";; p3-config-source-sha256: "
              (make-string 64 ?0)
              "\n(setq p3-config-loader-test--loaded 'stale)\n"))
    (setq p3-config-loader-test--loaded nil)
    (p3/config-load)
    (should (eq p3-config-loader-test--loaded 'fresh))
    (should-not (p3/config-cache-stale-p))))

(ert-deftest p3-config-loader-explicit-build-rebuilds-current-cache ()
  (p3-config-loader-test--with-files
      "#+begin_src emacs-lisp\n(setq p3-config-loader-test--explicit-build t)\n#+end_src\n"
    (p3/config-build)
    (should-not (p3/config-cache-stale-p))
    (let ((original-tangle (symbol-function 'org-babel-tangle-file))
          (calls 0))
      (cl-letf (((symbol-function 'org-babel-tangle-file)
                 (lambda (&rest args)
                   (setq calls (1+ calls))
                   (apply original-tangle args))))
        (p3/config-build))
      (should (= calls 1)))))
```

- [ ] **Step 8: Run the complete loader test file**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-loader-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: all loader tests PASS.

- [ ] **Step 9: Byte-compile the loader with warnings as errors**

Run:

```bash
emacs -Q --batch -L lisp \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile lisp/p3-config-loader.el
```

Expected: success with no warnings. If the compiler reports undeclared Org functions, fix declarations; do not add a top-level `(require 'org)` or `(require 'ob-tangle)`.

- [ ] **Step 10: Commit Task 2**

```bash
git add lisp/p3-config-loader.el test/p3-config-loader-test.el
git commit -m "feat: build config cache through guarded staging"
```

---

### Task 3: Bootstrap and Interactive Reload Wiring

**Files:**
- Modify: `init.el`
- Modify: `lisp/p3-core.el`
- Modify: `test/p3-core-test.el`
- Modify: `test/p3-config-test.el`

**Interfaces:**
- Consumes: `p3/config-build`, `p3/config-load-generated`, `p3/config-load`, `p3/config-source` from the loader.
- Produces: startup sequence `load-path -> p3-project -> p3-config-loader -> p3/config-load`.
- Produces: `p3/config-reload` = exactly one explicit build, then one direct generated-file load.

- [ ] **Step 1: Write a red delegation test for interactive reload**

Extend `test/p3-core-test.el`:

```elisp
(require 'cl-lib)

(ert-deftest p3-core-config-reload-builds-once-then-loads-directly ()
  (let (calls)
    (cl-letf (((symbol-function 'p3/config-build)
               (lambda () (push 'build calls)))
              ((symbol-function 'p3/config-load-generated)
               (lambda () (push 'load calls))))
      (p3/config-reload))
    (should (equal (nreverse calls) '(build load)))))
```

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-core-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: FAIL because current `p3/config-reload` delegates to old `p3/load-config`.

- [ ] **Step 2: Replace the old `p3/load-config` dependency in `p3-core.el`**

Change the module to require the loader and make reload explicit:

```elisp
;;; p3-core.el --- Shared helpers for the personal Emacs config -*- lexical-binding: t; -*-

(require 'p3-config-loader)

(defun p3/config-visit ()
  "Visit the authoritative literate Emacs configuration."
  (interactive)
  (find-file p3/config-source))

(defun p3/config-reload ()
  "Rebuild and reload the authoritative literate Emacs configuration."
  (interactive)
  (p3/config-build)
  (p3/config-load-generated)
  (message "Reloaded %s" p3/config-source))

(provide 'p3-core)

;;; p3-core.el ends here
```

Run the core tests. Expected: PASS.

- [ ] **Step 3: Write red bootstrap-order assertions for the new loader boundary**

Replace `p3-init-loads-project-foundation-before-literate-config` in `test/p3-config-test.el` with:

```elisp
(ert-deftest p3-init-loads-project-and-loader-before-literate-config ()
  (with-temp-buffer
    (insert-file-contents (expand-file-name "init.el" p3-config-test--root))
    (let ((load-path-position
           (progn
             (should (search-forward "(add-to-list 'load-path p3/lisp-directory)" nil t))
             (point)))
          project-position
          loader-position
          config-position)
      (setq project-position
            (progn
              (should (search-forward "(require 'p3-project)" nil t))
              (point)))
      (setq loader-position
            (progn
              (should (search-forward "(require 'p3-config-loader)" nil t))
              (point)))
      (setq config-position
            (progn
              (should (search-forward "(p3/config-load)" nil t))
              (point)))
      (should (< load-path-position project-position))
      (should (< project-position loader-position))
      (should (< loader-position config-position)))))

(ert-deftest p3-init-does-not-unconditionally-load-org-for-tangling ()
  (with-temp-buffer
    (insert-file-contents (expand-file-name "init.el" p3-config-test--root))
    (should-not (search-forward "(require 'ob-tangle)" nil t))
    (goto-char (point-min))
    (should-not (search-forward "(org-babel-tangle-file" nil t))
    (goto-char (point-min))
    (should-not (search-forward "(defun p3/load-config" nil t))))
```

Run `test/p3-config-test.el`. Expected: the new ordering test FAILS against the old bootstrap.

- [ ] **Step 4: Simplify `init.el` to bootstrap sequencing only**

Replace the current unconditional Org/Babel/config-path/tangle section with:

```elisp
(defconst p3/lisp-directory
  (expand-file-name "lisp" user-emacs-directory))
(add-to-list 'load-path p3/lisp-directory)

;; Establish native project semantics before the literate config or any
;; project-aware package has a chance to populate `project.el' caches.
(require 'p3-project)

;; Load the generated literate-config cache, rebuilding it only when its
;; embedded source fingerprint no longer matches config.org.
(require 'p3-config-loader)
(p3/config-load)
```

Remove from `init.el`:

```elisp
(require 'org)
(require 'ob-tangle)
(defconst p3/config-source ...)
(defconst p3/config-generated ...)
(defun p3/load-config ...)
(p3/load-config t)
```

Leave package/use-package bootstrap and the Consult/recentf/custom-file logic untouched.

- [ ] **Step 5: Run focused bootstrap/core tests**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-loader-test.el \
  -l test/p3-core-test.el \
  -l test/p3-config-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS.

- [ ] **Step 6: Byte-compile loader and core together**

Run:

```bash
emacs -Q --batch -L lisp \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile \
  lisp/p3-config-loader.el \
  lisp/p3-core.el
```

Expected: PASS.

- [ ] **Step 7: Commit Task 3**

```bash
git add init.el lisp/p3-core.el test/p3-core-test.el test/p3-config-test.el
git commit -m "refactor: load literate config through validated cache"
```

---

### Task 4: Real-Config Contract and Existing CI Gates

**Files:**
- Modify: `test/p3-config-test.el`
- Modify: `.github/workflows/emacs-tests.yml`
- Modify: `.github/workflows/windows-platform-tests.yml`

**Interfaces:**
- Consumes: complete loader/build/bootstrap implementation.
- Produces: real `config.org` integration proof and Linux/Windows regression gates.

- [ ] **Step 1: Route the real `config.org` smoke test through `p3/config-build`**

Replace the existing direct `org-babel-tangle-file` smoke test with a test that uses the production build path:

```elisp
(require 'p3-config-loader)

(ert-deftest p3-config-org-builds-through-production-cache-contract ()
  (let* ((directory (make-temp-file "p3-config-real-build-" t))
         (p3/config-source
          (expand-file-name "config.org" p3-config-test--root))
         (p3/config-generated
          (expand-file-name "config.el" directory)))
    (unwind-protect
        (progn
          (should (equal (p3/config-build) p3/config-generated))
          (should-not (p3/config-cache-stale-p))
          (with-temp-buffer
            (insert-file-contents p3/config-generated)
            (goto-char (point-min))
            (should (looking-at ";; p3-config-source-sha256: [0-9a-f]\\{64\\}$")))
          (p3-config-test--assert-readable-elisp p3/config-generated))
      (delete-directory directory t))))
```

Keep the existing `p3-config-test--assert-readable-elisp` helper and the other structural config tests.

Run `test/p3-config-test.el` and the loader tests together. Expected: PASS and one real 124-block tangle through the staged/single-target contract.

- [ ] **Step 2: Add the loader to the Ubuntu byte-compile gate**

In `.github/workflows/emacs-tests.yml`, compile it before `p3-core.el`:

```yaml
            lisp/p3-platform.el \
            lisp/p3-project.el \
            lisp/p3-config-loader.el \
            lisp/p3-core.el \
```

- [ ] **Step 3: Load loader tests first in the Ubuntu ERT gate**

Put the loader test file before `p3-config-test.el` so its module-load snapshot is taken before the config smoke tests themselves require Org:

```yaml
          emacs -Q --batch \
            -L lisp \
            -l test/p3-config-loader-test.el \
            -l test/p3-config-test.el \
            -l test/p3-project-test.el \
            -l test/p3-core-test.el \
            ... \
            -f ert-run-tests-batch-and-exit
```

Keep the remainder of the existing test-file list unchanged; do not split the Ubuntu workflow or add a second matrix.

- [ ] **Step 4: Extend the existing Windows workflow path filter narrowly**

Add:

```yaml
      - "lisp/p3-config-loader.el"
      - "test/p3-config-loader-test.el"
```

Keep existing platform/project paths.

- [ ] **Step 5: Byte-compile the loader in the existing Windows compile step**

Add:

```yaml
          lisp/p3-platform.el
          lisp/p3-project.el
          lisp/p3-config-loader.el
```

- [ ] **Step 6: Run one focused loader replacement test natively on Windows**

After the existing platform/project tests, add a step in the same job:

```yaml
      - name: Run Windows config-cache replacement test
        shell: powershell
        run: >-
          emacs -Q --batch -L lisp
          -l test/p3-config-loader-test.el
          --eval "(ert-run-tests-batch-and-exit \"^p3-config-loader-build-replaces-existing-cache$\")"
```

This exercises creation of a same-directory staged file, overwrite of an existing `config.el` through `rename-file ... t`, fingerprint correctness, and cleanup on native Windows. Do not run the whole loader suite a second time on Windows.

- [ ] **Step 7: Run the full local Ubuntu-equivalent gate once**

Run:

```bash
emacs -Q --batch -L lisp \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile \
  lisp/p3-platform.el \
  lisp/p3-project.el \
  lisp/p3-config-loader.el \
  lisp/p3-core.el \
  lisp/p3-python.el \
  lisp/p3-terminal.el \
  lisp/p3-ess.el \
  lisp/p3-r-tools.el \
  lisp/p3-gptel.el

emacs -Q --batch -L lisp \
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
  -f ert-run-tests-batch-and-exit
```

Expected: byte compilation PASS; complete ERT suite PASS.

- [ ] **Step 8: Commit Task 4**

```bash
git add test/p3-config-test.el \
  .github/workflows/emacs-tests.yml \
  .github/workflows/windows-platform-tests.yml
git commit -m "test: verify config cache across Linux and Windows"
```

---

## Final Verification and Review Gate

- [ ] Confirm the branch contains no tracked `config.el`, temporary stage file, `.elc`, or other generated cache artifact:

```bash
git status --short
git ls-files config.el '*.elc' '.p3-config-stage-*'
```

Expected: working tree clean; generated-file query returns nothing.

- [ ] Confirm the obsolete bootstrap API is gone from executable code/tests except historical docs:

```bash
git grep -n "p3/load-config" -- init.el lisp test
```

Expected: no matches.

- [ ] Confirm no production top-level Org/Babel require was introduced in the loader:

```bash
grep -n "^(require 'org)\|^(require 'ob-tangle)" lisp/p3-config-loader.el
```

Expected: no matches. The requires belong inside `p3/config-build` only.

- [ ] Run the complete Ubuntu-equivalent compile + ERT gate from Task 4 one final time after all edits.

- [ ] Push the completed branch once and use the existing GitHub Actions runs as the remote verification gate. Avoid iterative CI-only diagnosis; if either workflow fails, inspect the exact failing compile/test before making one bounded correction.

- [ ] Perform an adversarial review against `docs/superpowers/specs/2026-09-03-startup-tangle-cache-design.md`, with particular attention to:
  - stale-cache false negatives;
  - source changes during a build;
  - any tangle path that can bypass staging;
  - old-cache preservation before replacement;
  - runtime error semantics after replacement/load begins;
  - accidental `.elc` loading;
  - native-Windows overwrite behavior;
  - preservation of `p3-project` bootstrap ordering.

- [ ] Do not merge without explicit user approval.
