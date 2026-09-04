# Python Configuration Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move declarative Python package wiring into `p3-config-python.el` while preserving the current Python/Eglot/basedpyright workflow exactly and leaving `p3-python.el` as the reusable behavior library.

**Architecture:** `config.org` will exact-source load one new configuration owner, `p3-config-python.el`. That module exact-source loads `p3-python.el`, owns the existing built-in Python package declaration, `python-ts-mode` routing/hooks/bindings, Eglot package wiring, and the Python-specific Flake8 executable setting. `p3-python.el` remains behavior-only and unchanged unless compiler-only declarations are needed.

**Tech Stack:** Emacs Lisp, Emacs 29+, built-in `python.el`, `python-ts-mode`, Eglot, Flycheck, ERT, Org Babel config cache, `use-package`, GitHub Actions on Ubuntu and Windows.

**Spec:** `docs/superpowers/specs/2026-09-04-python-config-boundary-design.md`

## Global Constraints

- Preserve current Python behavior exactly; this is an ownership/extraction PR only.
- Do not change project interpreter discovery, `.venv`/`venv` precedence, Windows/Linux interpreter paths, managed basedpyright bootstrap, Eglot server registration, REPL behavior, diagnostics ownership, tree-sitter policy, Python keybindings, or package-management behavior.
- Keep `p3-python.el` as the single reusable Python behavior library; do not split it into additional files.
- `p3-config-python.el` is the single declarative Python configuration owner.
- Preserve `python-mode` and `python-ts-mode` symmetry for the three hooks and six source-buffer bindings specified in the design.
- Move only `flycheck-python-flake8-executable` out of the generic Flycheck block; leave global Flycheck enablement, exclusions, and checker threshold unchanged.
- Keep the Python module load in the current relative startup position between Projectile and Rainbow/Shell configuration.
- Legitimate Org Babel Python enablement remains in `config.org` and is not part of this extraction.
- Use the existing exact-source loader; add no registry, discovery, or generalized reload machinery.
- Use the existing CI package-install suppression during warnings-as-errors compilation. Do not bootstrap basedpyright or install optional packages merely to compile configuration.
- Generated `config.el` and `.elc` files remain ignored and untracked.
- Use one final Ubuntu/Windows CI cycle after local/static verification rather than iterative diagnostic pushes.

---

## File Map

- Create `lisp/p3-config-python.el` — declarative Python/Eglot/Flycheck configuration owner.
- Create `test/p3-config-python-test.el` — semantic source tests for the Python configuration boundary without bootstrapping basedpyright.
- Modify `config.org` — replace the inline Python/Eglot block with one module load and remove the Python-specific Flake8 setting from generic Flycheck.
- Modify `test/p3-config-test.el` — update ownership/module-count/startup-order structural assertions.
- Modify `.github/workflows/emacs-tests.yml` — compile the new module and load the new test file.
- Modify `.github/workflows/windows-platform-tests.yml` — trigger on Python boundary files and run the new source-level boundary tests.
- Do not modify `lisp/p3-python.el` or `test/p3-python-test.el` unless warnings-as-errors compilation proves a declaration-only adjustment is required.

---

### Task 1: Add semantic boundary tests and the Python configuration module

**Files:**
- Create: `test/p3-config-python-test.el`
- Create: `lisp/p3-config-python.el`

**Interfaces:**
- Consumes: `p3/config-load-module`; feature `p3-python`; existing `p3/python-*` commands; built-in Python maps/modes; Eglot commands.
- Produces: feature `p3-config-python`; one declarative Python configuration owner.

- [ ] **Step 1: Write failing source-level semantic tests**

Create `test/p3-config-python-test.el` with helpers that read tracked Emacs Lisp forms from `lisp/p3-config-python.el` without executing the module. Tests must assert:

```elisp
(p3/config-load-module 'p3-python)
```

The `use-package python` form must preserve these bindings exactly:

```elisp
(:map python-mode-map
      ("C-<return>" . nil)
      ("S-<return>" . python-shell-send-statement)
      ("C-c C-c" . p3/python-send-region-or-paragraph-and-step)
      ("C-<up>" . backward-paragraph)
      ("C-<down>" . forward-paragraph)
      ("C-c C-z" . p3/python-display-shell))
```

and these hooks exactly:

```elisp
((python-mode . p3/python-setup-project-interpreter)
 (python-mode . p3/python-eglot-ensure)
 (python-mode . p3/python-disable-flycheck))
```

The tests must also pin these custom values semantically:

```elisp
(python-indent-guess-indent-offset t)
(python-indent-guess-indent-offset-verbose nil)
(python-shell-interpreter (if (eq system-type 'windows-nt) "python" "python3"))
(python-shell-interpreter-args "-i")
```

For `python-ts-mode`, assert the conditional `when` form retains:

```elisp
(add-to-list 'auto-mode-alist '("\\.py\\'" . python-ts-mode))
(add-hook 'python-ts-mode-hook #'p3/python-setup-project-interpreter)
(add-hook 'python-ts-mode-hook #'p3/python-eglot-ensure)
(add-hook 'python-ts-mode-hook #'p3/python-disable-flycheck)
```

and these exact bindings inside `with-eval-after-load 'python`:

```elisp
(define-key python-ts-mode-map (kbd "C-<return>") nil)
(define-key python-ts-mode-map (kbd "S-<return>") #'python-shell-send-statement)
(define-key python-ts-mode-map (kbd "C-c C-c") #'p3/python-send-region-or-paragraph-and-step)
(define-key python-ts-mode-map (kbd "C-<up>") #'backward-paragraph)
(define-key python-ts-mode-map (kbd "C-<down>") #'forward-paragraph)
(define-key python-ts-mode-map (kbd "C-c C-z") #'p3/python-display-shell)
```

Add one direct symmetry test that normalizes the `python-mode` and `python-ts-mode` hook/binding pairs and asserts equivalent command targets rather than only testing that each symbol occurs somewhere.

Pin the Eglot bindings exactly:

```elisp
(:map eglot-mode-map
      ("C-c l r" . eglot-rename)
      ("C-c l a" . eglot-code-actions)
      ("C-c l f" . eglot-format))
```

Finally assert:

```elisp
(setq flycheck-python-flake8-executable "flake8")
```

is owned by `p3-config-python.el`.

- [ ] **Step 2: Verify RED**

```bash
emacs -Q --batch -L lisp -l test/p3-config-python-test.el -f ert-run-tests-batch-and-exit
```

Expected: failure because `lisp/p3-config-python.el` does not yet exist.

- [ ] **Step 3: Create `lisp/p3-config-python.el` by moving current forms without redesign**

Start the module with:

```elisp
;;; p3-config-python.el --- Python configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'p3-config-loader)

(p3/config-load-module 'p3-python)
```

Then copy the current `use-package python`, `python-ts-mode` conditional block, and `use-package eglot` forms from `config.org` semantically unchanged. Add:

```elisp
(setq flycheck-python-flake8-executable "flake8")
```

in the module so the final configured value remains unchanged.

End with:

```elisp
(provide 'p3-config-python)

;;; p3-config-python.el ends here
```

Do not change the platform-specific interpreter expression, hooks, commands, or keybindings.

- [ ] **Step 4: Verify GREEN for the new semantic suite**

```bash
emacs -Q --batch -L lisp -l test/p3-config-python-test.el -f ert-run-tests-batch-and-exit
```

Expected: all new boundary tests pass without starting Python, Eglot, or basedpyright.

- [ ] **Step 5: Verify compile closure without package installation**

Use the same compile suppression as the Ubuntu workflow:

```bash
emacs -Q --batch -L lisp \
  --eval '(require (quote use-package-ensure))' \
  --eval '(setq use-package-ensure-function (lambda (&rest _) t))' \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile lisp/p3-config-python.el
rm -f lisp/p3-config-python.elc
```

Expected: zero warnings/errors and no basedpyright bootstrap. If built-in map variables still need declarations in this compile mode, add only `defvar`/`declare-function` forms that do not alter runtime semantics.

- [ ] **Step 6: Commit**

```bash
git add lisp/p3-config-python.el test/p3-config-python-test.el
git commit -m "Add Python configuration module"
```

---

### Task 2: Route `config.org` through the new owner

**Files:**
- Modify: `config.org`
- Modify: `test/p3-config-test.el`
- Test: `test/p3-config-python-test.el`

**Interfaces:**
- Consumes: feature `p3-config-python` from Task 1.
- Produces: one Python configuration owner in `config.org`; generic Flycheck no longer owns a Python-specific setting.

- [ ] **Step 1: Update architecture tests first**

In `test/p3-config-test.el`:

1. change the config-module count expectation from six to seven and include `p3-config-python`;
2. replace expectations for inline `(use-package p3-python`, `(use-package python`, and `(use-package eglot` with:

```elisp
(p3/config-load-module 'p3-config-python)
```

3. add forbidden moved forms to `p3-config-moved-implementation-is-not-inline`:

```elisp
"(use-package p3-python"
"(use-package python"
"(use-package eglot"
"(add-hook 'python-ts-mode-hook"
"flycheck-python-flake8-executable"
```

4. add a Python one-owner test that asserts the module load occurs exactly in the existing Python section and that legitimate Org Babel `(python . t)` remains allowed;
5. extend startup-order assertions so the Python module remains after the existing Projectile configuration and before Rainbow/Shell configuration.

- [ ] **Step 2: Add ownership assertions to `test/p3-config-python-test.el`**

Assert `config.org` contains:

```elisp
(p3/config-load-module 'p3-config-python)
```

and does not contain direct `use-package python`, direct `use-package eglot`, Python mode hook wiring, `python-ts-mode` keybinding setup, or `flycheck-python-flake8-executable`. Do not reject the unrelated Org Babel `(python . t)` entry.

- [ ] **Step 3: Verify RED**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-test.el \
  -l test/p3-config-python-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: the new ownership/module-count tests fail because Python configuration is still inline.

- [ ] **Step 4: Remove only the Python-specific Flake8 assignment from generic Flycheck**

Change the existing Flycheck block from:

```elisp
(setq flycheck-global-modes '(not LaTeX-mode latex-mode org-mode))
(setq flycheck-python-flake8-executable "flake8")
(setq flycheck-checker-error-threshold 1000)
```

to:

```elisp
(setq flycheck-global-modes '(not LaTeX-mode latex-mode org-mode))
(setq flycheck-checker-error-threshold 1000)
```

Do not otherwise edit generic Flycheck configuration.

- [ ] **Step 5: Replace the inline Python block with module orchestration**

Replace the current `** Python` implementation with:

```org
** Python

Python package wiring, mode hooks, keybindings, Eglot integration, and
Python-specific diagnostic configuration live in =lisp/p3-config-python.el=.
Reusable interpreter, language-server, and REPL behavior remains in
=lisp/p3-python.el=.

#+BEGIN_SRC emacs-lisp
  (p3/config-load-module 'p3-config-python)
#+END_SRC
```

Keep this section exactly where the current Python section is, between Projectile and Rainbow.

- [ ] **Step 6: Verify no moved Python configuration remains inline**

```bash
git grep -n "use-package python\|use-package eglot\|python-ts-mode-hook\|flycheck-python-flake8-executable" -- config.org
```

Expected: no matches. Then verify the legitimate Babel entry still exists:

```bash
git grep -n "(python \. t)" -- config.org
```

Expected: one Org Babel match.

- [ ] **Step 7: Verify GREEN across affected suites**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-loader-test.el \
  -l test/p3-config-test.el \
  -l test/p3-config-python-test.el \
  -l test/p3-python-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: zero unexpected failures; existing environment-dependent skips are acceptable.

- [ ] **Step 8: Commit**

```bash
git add config.org test/p3-config-test.el test/p3-config-python-test.el
git commit -m "Route Python configuration through its module"
```

---

### Task 3: Wire Ubuntu and Windows CI coverage

**Files:**
- Modify: `.github/workflows/emacs-tests.yml`
- Modify: `.github/workflows/windows-platform-tests.yml`

**Interfaces:**
- Consumes: `lisp/p3-config-python.el`, `test/p3-config-python-test.el`.
- Produces: Ubuntu compile/full-suite coverage and Windows source-boundary coverage.

- [ ] **Step 1: Add Ubuntu compile/test entries**

In `.github/workflows/emacs-tests.yml`, add:

```text
lisp/p3-config-python.el
```

immediately before the existing `lisp/p3-python.el` compile entry, and add:

```text
-l test/p3-config-python-test.el
```

immediately before the existing `-l test/p3-python-test.el` test entry.

Preserve these existing compile-harness lines exactly:

```elisp
--eval '(require (quote use-package-ensure))'
--eval '(setq use-package-ensure-function (lambda (&rest _) t))'
--eval '(setq byte-compile-error-on-warn t)'
```

- [ ] **Step 2: Extend Windows path triggers**

Add these paths to `.github/workflows/windows-platform-tests.yml`:

```yaml
- "lisp/p3-config-python.el"
- "lisp/p3-python.el"
- "test/p3-config-python-test.el"
- "test/p3-python-test.el"
```

Do not broaden the Windows byte-compile command to optional Python/Eglot configuration; keep byte compilation limited to the existing portable boundary modules.

- [ ] **Step 3: Add the Python source-boundary suite to Windows architecture tests**

Add:

```text
-l test/p3-config-python-test.el
```

to `Run Windows config architecture tests`, adjacent to the ESS configuration boundary test.

- [ ] **Step 4: Static-check workflow changes**

```bash
git diff --check
git diff -- .github/workflows/emacs-tests.yml .github/workflows/windows-platform-tests.yml
```

Expected: only the new Python compile/test/path entries; no unrelated workflow behavior changes.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/emacs-tests.yml .github/workflows/windows-platform-tests.yml
git commit -m "Cover Python configuration boundary in CI"
```

---

### Task 4: Final verification and rejection-oriented review

**Files:** Verify all changed files; do not expand scope.

**Interfaces:** Consumes Tasks 1-3; produces a merge-ready PR candidate, with merge still requiring explicit user approval.

- [ ] **Step 1: Check branch scope and whitespace**

```bash
git diff --check master...HEAD
git diff --stat master...HEAD
```

Expected changed implementation files are limited to:

```text
lisp/p3-config-python.el
test/p3-config-python-test.el
config.org
test/p3-config-test.el
.github/workflows/emacs-tests.yml
.github/workflows/windows-platform-tests.yml
```

plus the approved Python spec and plan. `lisp/p3-python.el` and `test/p3-python-test.el` must remain unchanged unless a declaration-only compiler fix was proven necessary.

- [ ] **Step 2: Compare moved forms against `master`**

Compare the old inline Python block and Flake8 assignment in `master:config.org` against `HEAD:lisp/p3-config-python.el`. Reject any drift in:

- `python-mode` hooks or six bindings;
- Python custom values;
- `python-ts-mode` condition, auto-mode entry, hooks, or six bindings;
- Eglot bindings;
- Flake8 executable string.

- [ ] **Step 3: Run affected suites locally if Emacs is available**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-loader-test.el \
  -l test/p3-config-test.el \
  -l test/p3-config-python-test.el \
  -l test/p3-python-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: zero unexpected failures.

- [ ] **Step 4: Verify warnings-as-errors compile closure with installation suppressed**

```bash
emacs -Q --batch -L lisp \
  --eval '(require (quote use-package-ensure))' \
  --eval '(setq use-package-ensure-function (lambda (&rest _) t))' \
  --eval '(setq byte-compile-error-on-warn t)' \
  -f batch-byte-compile lisp/p3-config-python.el
rm -f lisp/p3-config-python.elc
```

Expected: zero warnings/errors, no optional package installation, and no basedpyright bootstrap.

- [ ] **Step 5: Confirm generated artifacts remain ignored/untracked**

```bash
git check-ignore -q config.el
git check-ignore -q lisp/example.elc
test -z "$(git ls-files 'config.el' '*.elc')"
```

- [ ] **Step 6: Push once, open the PR, and verify final merge-ref CI**

Ubuntu `Emacs tests` must complete successfully with warnings-as-errors compilation and zero unexpected ERT failures. Windows `Windows platform tests` must complete successfully, including `test/p3-config-python-test.el`. If CI fails, retrieve the exact failing job log and fix only the root cause without adding diagnostic machinery or using repeated speculative pushes.

- [ ] **Step 7: Final rejection-oriented review**

Reject the PR if any of the following are true:

- `config.org` still owns direct Python/Eglot package wiring;
- `p3-config-python.el` does not exact-source load `p3-python.el`;
- `p3-python.el` runtime behavior changed without an explicit design change;
- `.venv`/`venv`, basedpyright, Eglot, REPL, diagnostics, or tree-sitter behavior changed;
- `python-mode` and `python-ts-mode` hooks/bindings are no longer intentionally symmetrical;
- generic Flycheck still owns `flycheck-python-flake8-executable` or unrelated Flycheck policy moved;
- legitimate Org Babel Python enablement was removed;
- Python section startup position changed;
- optional packages or basedpyright are installed merely for CI compilation;
- generated artifacts are tracked;
- either final CI workflow has an unexpected failure.

If none apply, report merge-ready. Do not merge without explicit user approval.
