# Retire Projectile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove Projectile from the active Emacs configuration, replace its user-facing project prefix with native `project.el`, and move new R projects to `*.Rproj` project markers while preserving legacy `.projectile` boundaries.

**Architecture:** `p3-project.el` remains the startup-critical owner of project identity and marker policy. A new `p3-config-project.el` owns only native project keybindings, while `p3-r-tools.el` stops generating Projectile-specific files. Existing `.projectile` files remain recognized for compatibility, but no Projectile package/runtime code remains active.

**Tech Stack:** Emacs 29+ built-in `project.el`, Emacs Lisp, ERT, Org literate configuration, GitHub Actions on Ubuntu and native Windows.

**Spec:** `docs/superpowers/specs/2026-09-05-retire-projectile-design.md`

## Global Constraints

- Emacs 29+ remains the supported baseline.
- `project.el` must remain the only project framework and the sole source of project identity.
- Do not add a custom `project.el` backend or a Projectile fallback path.
- Remove Projectile from active configuration, but do not uninstall packages from user package directories.
- Keep `.projectile` in `project-vc-extra-root-markers` as legacy compatibility.
- Add `*.Rproj` as the forward R-project marker and stop generating `.projectile` in new R projects.
- Preserve `p3/project-root` and `p3/use-project-root-as-default-dir` interfaces and existing ESS, Python, R-tool, and terminal behavior.
- Bind `C-c p` and `s-p` directly to native `project-prefix-map`; leave `C-x p` and all native project command semantics unchanged.
- Do not reproduce Projectile command semantics, remembered-project state, keymap precedence, or shutdown behavior with compatibility machinery.
- After adoption, one Emacs restart is required to retire an already-running `projectile-mode`; `C-c r` alone is not required to do so.
- Preserve the Windows Rtools/MSYS2 marker-project file-enumeration contract.
- Use static/local verification before opening the PR; use the Ubuntu and Windows PR workflows as one coherent final CI gate rather than an iterative diagnostic loop.
- Do not modify historical specs/plans to erase Projectile from the migration history.

## File Structure

**Create**
- `lisp/p3-config-project.el` — declarative native project keybindings only.
- `test/p3-config-project-test.el` — focused owner/binding and config-delegation tests.

**Modify**
- `lisp/p3-project.el` — native marker policy; remove Projectile provider-defense machinery; add `*.Rproj` while retaining `.projectile`.
- `test/p3-project-test.el` — marker/root/file-boundary tests and removal of obsolete Projectile-hook coverage.
- `lisp/p3-r-tools.el` — stop scaffolding `.projectile`.
- `test/p3-r-tools-test.el` — prove new R projects contain `.Rproj` and not `.projectile`.
- `config.org` — replace the inline Projectile block with the native project config owner at the same orchestration position.
- `lisp/p3-commands.el` — add a concise native Project section to the keybinding atlas.
- `test/p3-commands-test.el` — pin the new atlas section.
- `test/p3-config-test.el` — update module count, ordering, owner assertions, and absence of inline Projectile configuration.
- `test/p3-project-windows-test.el` — exercise the forward `*.Rproj` marker on Windows.
- `.github/workflows/emacs-tests.yml` — compile/smoke/load the native project config owner and focused test.
- `.github/workflows/windows-platform-tests.yml` — add path triggers, compile the owner, and load its focused test.

---

### Task 1: Make native project markers independent of Projectile

**Files:**
- Modify: `test/p3-project-test.el`
- Modify: `lisp/p3-project.el`

**Interfaces:**
- Consumes: built-in `project-current`, `project-root`, `project-files`, and `project-vc-extra-root-markers`.
- Produces: unchanged `p3/project-root` and `p3/use-project-root-as-default-dir`; marker policy recognizing both legacy `.projectile` and forward `*.Rproj`.

- [ ] **Step 1: Add failing forward-marker and runtime-retirement tests before changing production code**

Replace the existing `p3-project-marker-only-project-is-detected-from-descendant` test with the explicitly named compatibility test below, then add the two `*.Rproj` tests and the source-policy test:

```elisp
(ert-deftest p3-project-legacy-projectile-marker-is-detected-from-descendant ()
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

(ert-deftest p3-project-rproj-marker-only-project-is-detected-from-descendant ()
  (let* ((root (make-temp-file "p3-project-rproj-" t))
         (child (expand-file-name "R/subdir" root)))
    (unwind-protect
        (progn
          (make-directory child t)
          (with-temp-file (expand-file-name "analysis.Rproj" root))
          (let ((default-directory child))
            (should
             (equal (p3-project-test--canonical-directory (p3/project-root))
                    (p3-project-test--canonical-directory root)))))
      (delete-directory root t))))

(ert-deftest p3-project-inner-rproj-marker-bounds-project-files ()
  (skip-unless (executable-find "git"))
  (let* ((outer (make-temp-file "p3-project-outer-rproj-" t))
         (inner (expand-file-name "analysis" outer))
         (child (expand-file-name "R/subdir" inner))
         (inner-file (expand-file-name "R/inside.R" inner))
         (outer-file (expand-file-name "outside.R" outer)))
    (unwind-protect
        (progn
          (should
           (zerop (call-process "git" nil nil nil "-C" outer "init" "-q")))
          (make-directory child t)
          (with-temp-file (expand-file-name "analysis.Rproj" inner))
          (with-temp-file inner-file
            (insert "inside <- TRUE\n"))
          (with-temp-file outer-file
            (insert "outside <- TRUE\n"))
          (let* ((default-directory child)
                 (project (project-current nil))
                 (files (mapcar #'file-truename (project-files project))))
            (should project)
            (should
             (equal (p3-project-test--canonical-directory (project-root project))
                    (p3-project-test--canonical-directory inner)))
            (should (member (file-truename inner-file) files))
            (should-not (member (file-truename outer-file) files))))
      (delete-directory outer t))))

(ert-deftest p3-project-source-has-no-projectile-runtime-policy ()
  (let ((path (expand-file-name "lisp/p3-project.el" p3-project-test--root)))
    (with-temp-buffer
      (insert-file-contents path)
      (let ((contents (buffer-string)))
        (dolist (forbidden '("project-projectile"
                            "projectile-mode-hook"
                            "p3/project-keep-native-provider"))
          (should-not (string-match-p (regexp-quote forbidden) contents)))
        (should (string-match-p
                 (regexp-quote "\".projectile\"") contents))
        (should (string-match-p
                 (regexp-quote "\"*.Rproj\"") contents))))))
```

Keep `p3-project-projectile-mode-hook-restores-native-provider` in place for this red run; remove it only when the provider-defense production code is removed in Step 3.

- [ ] **Step 2: Run the focused project tests and verify the new tests fail**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-project-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected failures:
- `p3-project-rproj-marker-only-project-is-detected-from-descendant` because `*.Rproj` is not registered yet;
- `p3-project-inner-rproj-marker-bounds-project-files` for the same reason;
- `p3-project-source-has-no-projectile-runtime-policy` because the provider-defense code still exists.

The legacy `.projectile` compatibility and existing project helper tests must still pass.

- [ ] **Step 3: Remove Projectile provider-defense code and register the forward marker**

Change the top of `lisp/p3-project.el` to:

```elisp
;;; p3-project.el --- Shared project identity for the personal Emacs config -*- lexical-binding: t; -*-

(require 'project)

(unless (boundp 'project-vc-extra-root-markers)
  (error "P3 project support requires Emacs 29 or newer"))

(dolist (marker '(".projectile" "*.Rproj"))
  (add-to-list 'project-vc-extra-root-markers marker))
```

Delete these exact existing forms and comments from `lisp/p3-project.el`:

```elisp
(declare-function project-projectile "projectile" (directory))

(defun p3/project-keep-native-provider ()
  "Keep Projectile from overriding native `project.el' project discovery."
  (remove-hook 'project-find-functions #'project-projectile))

;; Projectile intentionally registers itself as a project.el provider whenever
;; `projectile-mode' changes state.  Keep its UI and commands, but remove that
;; provider after the mode has finished updating its hooks.
(add-hook 'projectile-mode-hook #'p3/project-keep-native-provider)
(p3/project-keep-native-provider)
```

Leave these existing definitions unchanged:

```elisp
(defun p3/project-root ()
  "Return the current built-in `project.el' root, if any."
  (when-let ((project (project-current nil)))
    (project-root project)))

(defun p3/use-project-root-as-default-dir ()
  "Use the current project root as the buffer's default directory."
  (when-let ((root (p3/project-root)))
    (setq-local default-directory root)))
```

Remove the obsolete `p3-project-projectile-mode-hook-restores-native-provider` test from `test/p3-project-test.el`; that behavior is intentionally deleted rather than replaced.

- [ ] **Step 4: Run the focused project tests and verify marker/root/file semantics pass**

Run the same command from Step 2.

Expected: PASS, including legacy `.projectile` detection, `*.Rproj` detection, nested `*.Rproj` root/file boundaries, and the assertion that no Projectile runtime policy remains in `p3-project.el`.

- [ ] **Step 5: Commit the native project semantic change**

```bash
git add lisp/p3-project.el test/p3-project-test.el
git commit -m "Retire Projectile project provider policy"
```

---

### Task 2: Stop scaffolding Projectile-specific R project files

**Files:**
- Modify: `test/p3-r-tools-test.el`
- Modify: `lisp/p3-r-tools.el`

**Interfaces:**
- Consumes: the existing `<project-name>.Rproj` template generated by `p3-r-new-project` and the `*.Rproj` marker policy from Task 1.
- Produces: newly scaffolded R projects containing `<project-name>.Rproj` but no `.projectile` sentinel.

- [ ] **Step 1: Change the R scaffolding test to require the new forward state**

In `p3-r-new-analysis-project-generates-expected-files`, use these assertions:

```elisp
(should (file-exists-p (expand-file-name "analysis-demo.Rproj" root)))
(should-not (file-exists-p (expand-file-name ".projectile" root)))
(should (file-exists-p (expand-file-name "R/01_prepareData.R" root)))
(should (file-exists-p (expand-file-name "R/utils.R" root)))
(should-not (file-exists-p (expand-file-name "_targets.R" root)))
```

Keep the existing generated-script content assertion unchanged.

- [ ] **Step 2: Run the focused R-tools tests and verify the changed assertion fails**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-r-tools-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: `p3-r-new-analysis-project-generates-expected-files` fails because `.projectile` is still emitted by `p3-r--common-project-files`.

- [ ] **Step 3: Remove `.projectile` from the common R project scaffold**

Replace the current constant with:

```elisp
(defconst p3-r--common-project-files
  '((:path "{{project-name}}.Rproj" :template "project.Rproj.tmpl")
    (:path ".gitignore" :template "gitignore.tmpl")
    (:path "R/01_prepareData.R" :template "script.R.tmpl"
           :title "Preprocess data")
    (:path "R/02_computeResults.R" :template "script.R.tmpl"
           :title "Compute results"))
  "Files shared by all R project profiles.")
```

Do not rename, reformat, or otherwise alter the `.Rproj` template or profile structure.

- [ ] **Step 4: Run the focused R-tools and project tests**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-project-test.el \
  -l test/p3-r-tools-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS.

- [ ] **Step 5: Commit the scaffolding migration**

```bash
git add lisp/p3-r-tools.el test/p3-r-tools-test.el
git commit -m "Use Rproj files as forward project markers"
```

---

### Task 3: Replace the Projectile UI layer with native project configuration

**Files:**
- Create: `test/p3-config-project-test.el`
- Create: `lisp/p3-config-project.el`
- Modify: `config.org`
- Modify: `test/p3-config-test.el`
- Modify: `lisp/p3-commands.el`
- Modify: `test/p3-commands-test.el`

**Interfaces:**
- Consumes: built-in `project-prefix-map`, startup-loaded `p3-project.el`, and existing `p3/config-load-module` orchestration.
- Produces: `p3-config-project` feature; global aliases `C-c p` and `s-p` to the exact native `project-prefix-map`; one config owner in the current Presentation → Project → Python position.

- [ ] **Step 1: Create the focused owner test before creating the owner**

Create `test/p3-config-project-test.el` with:

```elisp
;;; p3-config-project-test.el --- Native project config boundary tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'project)
(require 'p3-config-loader)

(defconst p3-config-project-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(defun p3-config-project-test--contents (relative)
  "Return contents of repository file RELATIVE."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name relative p3-config-project-test--root))
    (buffer-string)))

(ert-deftest p3-config-project-binds-native-project-prefixes ()
  (let ((p3/config-lisp-directory
         (expand-file-name "lisp" p3-config-project-test--root))
        (old-c-c-p (lookup-key global-map (kbd "C-c p")))
        (old-s-p (lookup-key global-map (kbd "s-p"))))
    (unwind-protect
        (progn
          (p3/config-load-module 'p3-config-project)
          (should (featurep 'p3-config-project))
          (should (eq (lookup-key global-map (kbd "C-c p"))
                      project-prefix-map))
          (should (eq (lookup-key global-map (kbd "s-p"))
                      project-prefix-map))
          (should (eq (lookup-key global-map (kbd "C-x p"))
                      project-prefix-map)))
      (define-key global-map (kbd "C-c p") old-c-c-p)
      (define-key global-map (kbd "s-p") old-s-p))))

(ert-deftest p3-config-project-config-org-has-one-native-owner ()
  (let ((contents (p3-config-project-test--contents "config.org")))
    (should
     (string-match-p
      (regexp-quote "(p3/config-load-module 'p3-config-project)")
      contents))
    (dolist (forbidden '("(use-package projectile"
                          "p3/projectile-r-project-file-p"
                          "projectile-command-map"
                          "projectile-register-project-type"
                          "(projectile-mode +1)"))
      (should-not (string-match-p (regexp-quote forbidden) contents)))))

(provide 'p3-config-project-test)

;;; p3-config-project-test.el ends here
```

- [ ] **Step 2: Update architecture and atlas tests before implementation**

In `test/p3-config-test.el`:

1. In both `p3-config-org-subsystem-order-is-explicit` and `p3-config-python-preserves-subsystem-timing`, replace the Projectile lookup with:

```elisp
(project-config
 (p3-config-test--position
  "(p3/config-load-module 'p3-config-project)" contents))
```

and use `project-config` in the existing ordering assertions.

2. Rename `p3-config-org-source-loads-twelve-config-modules` to `p3-config-org-source-loads-thirteen-config-modules`, change the expected count from `12` to `13`, and make the owner list:

```elisp
'(p3-config-base p3-config-editing p3-config-completion
  p3-config-ess p3-config-gptel p3-config-org
  p3-config-org-roam p3-config-org-present p3-config-project
  p3-config-python p3-config-terminal p3-config-workspace p3-config-git)
```

3. Add these forms to `p3-config-moved-implementation-is-not-inline`:

```elisp
"(use-package projectile"
"(defun p3/projectile-r-project-file-p"
"projectile-command-map"
"projectile-register-project-type"
"(projectile-mode +1)"
```

4. Add:

```elisp
(ert-deftest p3-config-project-orchestration-has-one-owner ()
  (let* ((contents (p3-config-test--contents "config.org"))
         (owner "(p3/config-load-module 'p3-config-project)"))
    (should (= 1 (p3-config-test--count-occurrences owner contents)))
    (dolist (forbidden '("(use-package projectile"
                          "p3/projectile-r-project-file-p"
                          "projectile-command-map"
                          "projectile-register-project-type"
                          "(projectile-mode +1)"))
      (should-not (string-match-p (regexp-quote forbidden) contents)))))
```

In `test/p3-commands-test.el`, add:

```elisp
(ert-deftest p3-commands-keybinding-atlas-documents-native-project-prefix ()
  (let ((section (assoc "Project" p3/keybinding-sections)))
    (should section)
    (should (equal (cdr (assoc "C-c p / C-x p" (cdr section)))
                   "native project commands"))
    (should (equal (cdr (assoc "s-p" (cdr section)))
                   "native project commands"))))
```

- [ ] **Step 3: Run the focused config/architecture tests and verify they fail before implementation**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-project-test.el \
  -l test/p3-config-test.el \
  -l test/p3-commands-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected failures: the owner file does not exist, `config.org` still contains Projectile, the config owner count is still 12, and the atlas has no Project section.

- [ ] **Step 4: Create the native project config owner**

Create `lisp/p3-config-project.el` exactly as:

```elisp
;;; p3-config-project.el --- Native project configuration -*- lexical-binding: t; -*-

(require 'project)

(global-set-key (kbd "C-c p") project-prefix-map)
(global-set-key (kbd "s-p") project-prefix-map)

(provide 'p3-config-project)

;;; p3-config-project.el ends here
```

Do not add `use-package projectile`, compatibility wrappers, custom project commands, or a new minor mode.

- [ ] **Step 5: Replace the inline Projectile block in `config.org` at the same orchestration position**

Replace the entire current `** Projectile` section with:

```org
** Project

Native project identity is established early by =lisp/p3-project.el=.
User-facing project bindings live in =lisp/p3-config-project.el= and use the
built-in =project.el= command map.

#+BEGIN_SRC emacs-lisp
  (p3/config-load-module 'p3-config-project)
#+END_SRC
```

Keep this section after Presentation and before Python.

- [ ] **Step 6: Add the concise Project section to the keybinding atlas**

In `lisp/p3-commands.el`, add immediately after the `Global` section:

```elisp
("Project"
 ("C-c p / C-x p" . "native project commands")
 ("s-p" . "native project commands"))
```

Do not enumerate the entire native project prefix.

- [ ] **Step 7: Run focused project/config/atlas tests**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-project-test.el \
  -l test/p3-config-project-test.el \
  -l test/p3-config-test.el \
  -l test/p3-commands-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS. `C-c p`, `s-p`, and `C-x p` resolve to the same built-in `project-prefix-map`, and `config.org` has exactly one native project config owner with no inline Projectile runtime forms.

- [ ] **Step 8: Commit the native project UI/config boundary**

```bash
git add \
  lisp/p3-config-project.el \
  test/p3-config-project-test.el \
  config.org \
  test/p3-config-test.el \
  lisp/p3-commands.el \
  test/p3-commands-test.el
git commit -m "Replace Projectile UI with project.el"
```

---

### Task 4: Make Windows and CI coverage durable for the new boundary

**Files:**
- Modify: `test/p3-project-windows-test.el`
- Modify: `.github/workflows/emacs-tests.yml`
- Modify: `.github/workflows/windows-platform-tests.yml`

**Interfaces:**
- Consumes: `p3-config-project` from Task 3 and the `*.Rproj` marker policy from Task 1.
- Produces: native Windows evidence that marker-only project discovery/file enumeration works with `*.Rproj`; CI triggers and compilation/test coverage for future isolated project-config edits.

- [ ] **Step 1: Change the native Windows marker test to exercise the forward marker**

In `test/p3-project-windows-test.el`, replace:

```elisp
(with-temp-file (expand-file-name ".projectile" root))
```

with:

```elisp
(with-temp-file (expand-file-name "windows-test.Rproj" root))
```

Leave the Rtools/MSYS2 setup, root assertion, and `project-files` enumeration assertion unchanged.

- [ ] **Step 2: Extend the Ubuntu workflow for the new project config owner**

In `.github/workflows/emacs-tests.yml`:

1. Add `lisp/p3-config-project.el` to `Byte-compile extracted modules`, immediately after `lisp/p3-project.el`.

2. Add this smoke step before the existing Python smoke:

```yaml
      - name: Smoke-load Project configuration boundary
        run: |
          emacs -Q --batch \
            -L lisp \
            -l lisp/p3-config-project.el \
            --eval '(unless (and (featurep (quote p3-config-project)) (eq (lookup-key global-map (kbd "C-c p")) project-prefix-map) (eq (lookup-key global-map (kbd "s-p")) project-prefix-map) (eq (lookup-key global-map (kbd "C-x p")) project-prefix-map)) (kill-emacs 1))'
```

3. Add `-l test/p3-config-project-test.el` to the full ERT suite immediately after `-l test/p3-project-test.el`.

- [ ] **Step 3: Extend the Windows workflow path filters and gates**

In `.github/workflows/windows-platform-tests.yml`:

1. Add these `pull_request.paths` entries next to the existing project files:

```yaml
      - "lisp/p3-config-project.el"
      - "test/p3-config-project-test.el"
```

2. Add `lisp/p3-config-project.el` to `Byte-compile Windows boundary modules` immediately after `lisp/p3-project.el`.

3. Add `-l test/p3-config-project-test.el` to `Run Windows config architecture tests` immediately after `-l test/p3-config-test.el`.

Do not add a new workflow or a second Windows job.

- [ ] **Step 4: Run all locally runnable project/config tests before opening a PR**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-loader-test.el \
  -l test/p3-config-test.el \
  -l test/p3-project-test.el \
  -l test/p3-config-project-test.el \
  -l test/p3-core-test.el \
  -l test/p3-platform-test.el \
  -l test/p3-config-python-test.el \
  -l test/p3-python-test.el \
  -l test/p3-terminal-test.el \
  -l test/p3-config-terminal-test.el \
  -l test/p3-ess-test.el \
  -l test/p3-r-tools-test.el \
  -l test/p3-commands-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS on the current platform. `p3-project-windows-test.el` is not proof on non-Windows; the native Windows PR workflow remains authoritative for that contract.

- [ ] **Step 5: Commit the CI/platform durability changes**

```bash
git add \
  test/p3-project-windows-test.el \
  .github/workflows/emacs-tests.yml \
  .github/workflows/windows-platform-tests.yml
git commit -m "Verify native project boundary across platforms"
```

---

### Task 5: Final static audit, PR gate, and adversarial review

**Files:**
- Verify all files changed in Tasks 1–4.
- Do not introduce production changes after the final PR-triggering commit unless verification demonstrates a real defect.

**Interfaces:**
- Consumes: the complete implementation and tests from Tasks 1–4.
- Produces: one reviewable PR with exact-head Ubuntu and Windows evidence; no merge without explicit user approval.

- [ ] **Step 1: Audit active runtime source for residual Projectile dependencies**

Run:

```bash
git grep -n -E \
  'use-package projectile|projectile-mode|projectile-command-map|projectile-register-project-type|project-projectile|p3/projectile-r-project-file-p' \
  -- config.org init.el lisp
```

Expected: no matches.

Then run:

```bash
git grep -n '\.projectile' -- config.org init.el lisp
```

Expected: only the intentional legacy compatibility marker in `lisp/p3-project.el`; `lisp/p3-r-tools.el` must not emit `.projectile`.

- [ ] **Step 2: Verify the exact config orchestration shape**

Run:

```bash
git grep -n "p3-config-project" -- config.org lisp test .github
```

Expected:
- one `config.org` owner load;
- one owner source file;
- focused and architecture tests;
- Ubuntu compile/smoke/full-suite coverage;
- Windows path/compile/test coverage.

Verify `config.org` ordering remains:

```text
Org -> Org-roam -> Poly-R -> Presentation -> Project -> Python -> Rainbow -> Shell
```

- [ ] **Step 3: Run the full Ubuntu-equivalent ERT suite before opening the PR**

Run:

```bash
emacs -Q --batch \
  -L lisp \
  -l test/p3-config-loader-test.el \
  -l test/p3-config-test.el \
  -l test/p3-config-ess-test.el \
  -l test/p3-project-test.el \
  -l test/p3-config-project-test.el \
  -l test/p3-core-test.el \
  -l test/p3-platform-test.el \
  -l test/p3-config-python-test.el \
  -l test/p3-python-test.el \
  -l test/p3-terminal-test.el \
  -l test/p3-config-terminal-test.el \
  -l test/p3-ess-test.el \
  -l test/p3-gptel-test.el \
  -l test/p3-config-gptel-test.el \
  -l test/p3-r-tools-test.el \
  -l test/p3-org-test.el \
  -l test/p3-config-org-test.el \
  -l test/p3-org-roam-test.el \
  -l test/p3-config-org-roam-test.el \
  -l test/p3-org-present-test.el \
  -l test/p3-config-org-present-test.el \
  -l test/p3-org-export-test.el \
  -l test/p3-commands-test.el \
  -l test/p3-git-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: zero unexpected failures. Existing intentional skips for unavailable platform/tool contracts are acceptable.

- [ ] **Step 4: Open PR #19 only after static/local verification is clean**

Use title:

```text
Retire Projectile in favor of project.el
```

Use body:

```markdown
## Summary

- remove Projectile from active Emacs configuration and project identity/runtime policy
- bind `C-c p` and `s-p` directly to the built-in `project-prefix-map`; leave native `C-x p` unchanged
- use `*.Rproj` as the forward marker for generated R projects and stop creating `.projectile`
- retain `.projectile` only as a legacy `project.el` compatibility marker
- preserve existing ESS, Python, R-tool, terminal, and Windows project-root contracts

## Intentional transition behavior

- native `project.el` switching and remembered-project behavior is not made Projectile-compatible
- global project aliases use the global map rather than a Projectile minor-mode map
- if `projectile-mode` is already active when this change is adopted, restart Emacs once; `C-c r` alone is not expected to retire that existing session state
- no Projectile cache importer, runtime shutdown shim, or package uninstall mechanism is added

## Verification

- focused ERT coverage proves legacy `.projectile` compatibility, `*.Rproj` project detection, nested `project-files` boundaries, native project prefix bindings, and R scaffold output
- Ubuntu CI byte-compiles and smoke-loads the native project config owner and runs the full ERT suite
- Windows CI exercises `*.Rproj` marker detection/file enumeration after normal Rtools/MSYS2 setup and includes the new config owner in durable path/compile/test coverage

Do not merge without explicit approval.
```

Opening the PR is the single intended trigger for the final Ubuntu and Windows Actions gate.

- [ ] **Step 5: Verify both workflows on the exact PR head**

Require:
- Ubuntu `Emacs tests`: success, including warnings-as-errors byte compilation, Project smoke, and full ERT suite.
- `Windows platform tests`: success, including `*.Rproj` marker detection/file enumeration, project config byte compilation, focused project config test, and architecture tests.

If a workflow fails, inspect the specific failing step/log and fix only the demonstrated root cause. Do not add diagnostic workflows or repeatedly rerun full CI without a code/test change that addresses the failure.

- [ ] **Step 6: Perform an adversarial final review before asking for merge approval**

Review the exact PR diff against `docs/superpowers/specs/2026-09-05-retire-projectile-design.md` and verify:
- no hidden Projectile runtime/reference remains in active code;
- `.projectile` compatibility was not accidentally removed;
- R scaffolding no longer emits `.projectile`;
- native project file boundaries are tested, not just roots;
- no custom project backend or Projectile emulation was introduced;
- no ESS/Python/terminal/R workflow drift is present;
- Windows workflow triggers remain durable for isolated future project-config edits;
- historical migration docs remain untouched apart from the new approved spec/plan.

Do not merge PR #19 without explicit user approval.
