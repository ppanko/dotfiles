# ESS Configuration Boundary Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move declarative ESS/R-mode configuration into `p3-config-ess.el` while preserving the current R/ESS workflow and leaving `p3-ess.el` focused on project/session/process ownership.

**Architecture:** `config.org` exact-source loads one new configuration owner, `p3-config-ess.el`. That module exact-source loads `p3-ess.el` and `p3-r-tools.el`, explicitly invokes `p3/ess-setup`, owns ESS package wiring and ESS-specific Company configuration, and leaves Windows R executable selection in `config.org` immediately afterward. Existing process/session code and R workflow commands remain behaviorally unchanged.

**Tech Stack:** Emacs Lisp, Emacs 29+, Org Babel config cache, `use-package`, ESS, Company, ERT, GitHub Actions on Ubuntu and Windows.

**Spec:** `docs/superpowers/specs/2026-09-04-ess-config-boundary-design.md`

## Global Constraints

- Preserve current ESS/R behavior; this is an extraction/refactoring PR.
- Do not fix the existing `company-dabbrev` compatibility error.
- Do not change Company backend composition, ESS process/session semantics, R startup arguments, Lintr/Flycheck policy, ESS font-lock, project identity, R workflow commands, window placement, keybindings, package management, Python, Org, terminal, or Projectile behavior.
- Keep `p3/windows-configure-r-program` in `config.org` immediately after the ESS module load.
- Keep the narrow `inferior-ess-r-mode` display rule unchanged in `p3-config-workspace.el`.
- Use the existing exact-source module loader; add no registry, discovery, or generalized reload mechanism.
- Move `p3/ess-inferior-mode-setup` into `p3-config-ess.el`; `p3-ess.el` retains process/session ownership only.
- `p3-config-ess.el` must explicitly call `p3/ess-setup` after exact-source loading `p3-ess.el`.
- Preserve this exact Company backend value:

```elisp
'((:separate
   company-R-library company-R-args company-R-objects
   company-dabbrev-code
   :with company-yasnippet)
  company-capf)
```

- Generated `config.el` and `.elc` files remain ignored and untracked.
- Use one final Ubuntu/Windows CI cycle after local/static verification rather than iterative CI diagnostics.

---

## File Map

- Create `lisp/p3-config-ess.el` — declarative ESS/R configuration owner.
- Create `test/p3-config-ess-test.el` — semantic source tests that do not require optional third-party packages at runtime.
- Modify `lisp/p3-ess.el` — remove inferior-buffer configuration only.
- Modify `lisp/p3-config-completion.el` — remove ESS-specific Company ownership only.
- Modify `config.org` — remove the early `p3-r-tools` stanza and inline ESS implementation; load `p3-config-ess` instead.
- Modify `test/p3-config-test.el` — update ownership/order assertions.
- Modify `.github/workflows/emacs-tests.yml` — compile/test the new module.
- Modify `.github/workflows/windows-platform-tests.yml` — trigger on ESS boundary files and run source-level ESS boundary tests.

---

### Task 1: Add semantic tests and the new ESS configuration module

**Files:**
- Create: `test/p3-config-ess-test.el`
- Create: `lisp/p3-config-ess.el`

**Interfaces:**
- Consumes: `p3/config-load-module`, `p3/ess-setup`, `p3-r-command-map`, existing `p3-r-*` commands.
- Produces: feature `p3-config-ess`; functions `p3/ess-inferior-mode-setup`, `p3/ess-company-config`, `compile-rmd`; variable `p3/r-company-backends`.

- [ ] **Step 1: Write failing semantic source tests**

Create `test/p3-config-ess-test.el` to read Lisp forms from the tracked source without loading optional ESS/Company packages. It must assert the exact Company backend value, exact ESS hook/binding lists, explicit `p3/ess-setup`, the sensitive `setq` pairs, `compile-rmd` hooks, and inferior-buffer setup.

- [ ] **Step 2: Verify RED**

```bash
emacs -Q --batch -L lisp -l test/p3-config-ess-test.el -f ert-run-tests-batch-and-exit
```

Expected: failure because `lisp/p3-config-ess.el` does not yet exist.

- [ ] **Step 3: Create `lisp/p3-config-ess.el` with the current ESS configuration values**

The module must:

```elisp
(require 'use-package)
(require 'p3-config-loader)
(p3/config-load-module 'p3-ess)
(declare-function p3/ess-setup "p3-ess" ())
(p3/ess-setup)
(p3/config-load-module 'p3-r-tools)
(keymap-global-set "C-c R" p3-r-command-map)
```

It then defines the exact `p3/r-company-backends`, `p3/ess-company-config`, `p3/ess-inferior-mode-setup`, the existing `use-package ess-r-mode` hook/bind/config values, and unchanged `compile-rmd` hooks.

- [ ] **Step 4: Verify GREEN and compile closure**

```bash
emacs -Q --batch -L lisp -l test/p3-config-ess-test.el -f ert-run-tests-batch-and-exit
emacs -Q --batch -L lisp --eval '(setq byte-compile-error-on-warn t)' -f batch-byte-compile lisp/p3-config-ess.el
rm -f lisp/p3-config-ess.elc
```

Expected: all new tests pass and byte compilation has zero warnings/errors. Add only compiler declarations required for external ESS/Company symbols; do not change behavior.

- [ ] **Step 5: Commit**

```bash
git add lisp/p3-config-ess.el test/p3-config-ess-test.el
git commit -m "Add ESS configuration module"
```

---

### Task 2: Remove configuration from old owners

**Files:**
- Modify: `lisp/p3-ess.el`
- Modify: `lisp/p3-config-completion.el`
- Modify: `test/p3-config-ess-test.el`

**Interfaces:**
- Consumes: new owner from Task 1.
- Produces: process/session-only `p3-ess.el`; generic-only `p3-config-completion.el`.

- [ ] **Step 1: Add failing ownership tests**

Append tests asserting `p3-ess.el` no longer contains `p3/ess-inferior-mode-setup`, `ansi-color-for-comint-mode`, or `smartparens-mode`; and `p3-config-completion.el` no longer contains `p3/r-company-backends`, `p3/ess-company-config`, or the ESS Company backend symbols.

- [ ] **Step 2: Verify RED**

```bash
emacs -Q --batch -L lisp -l test/p3-config-ess-test.el -f ert-run-tests-batch-and-exit
```

Expected: the ownership tests fail on the current old owners.

- [ ] **Step 3: Remove only buffer configuration from `p3-ess.el`**

Delete:

```elisp
(declare-function smartparens-mode "smartparens" (&optional arg))
(defvar ansi-color-for-comint-mode)
(defun p3/ess-inferior-mode-setup ()
  "Apply personal defaults to an inferior ESS buffer."
  (setq-local ansi-color-for-comint-mode 'filter)
  (smartparens-mode 1))
```

Do not alter project/process behavior or `p3/ess-setup`.

- [ ] **Step 4: Remove only ESS-specific Company ownership from completion**

Remove the now-unused `company-backends` declaration and replace the Company block with:

```elisp
(use-package company
  :hook (after-init . global-company-mode)
  :config
  (setq company-dabbrev-downcase nil))
```

- [ ] **Step 5: Verify GREEN plus existing ESS behavior**

```bash
emacs -Q --batch -L lisp -l test/p3-config-ess-test.el -l test/p3-ess-test.el -f ert-run-tests-batch-and-exit
```

- [ ] **Step 6: Commit**

```bash
git add lisp/p3-ess.el lisp/p3-config-completion.el test/p3-config-ess-test.el
git commit -m "Separate ESS behavior from configuration"
```

---

### Task 3: Replace inline ESS configuration with module orchestration

**Files:**
- Modify: `config.org`
- Modify: `test/p3-config-test.el`

**Interfaces:**
- Consumes: `p3-config-ess` from Task 1.
- Produces: one ESS module load in `config.org`; Windows R selection stays immediately after it.

- [ ] **Step 1: Update tests before changing `config.org`**

Update `p3-config-org-delegates-custom-subsystems-to-modules` so `p3-ess` and `ess-r-mode` are no longer expected inline, and assert:

```elisp
(should (string-match-p
         (regexp-quote "(p3/config-load-module 'p3-config-ess)")
         contents))
```

Add `p3-config-ess` to ordering checks, rename the five-module test to six modules, add old ESS/R-tools inline forms to the forbidden list, and add a one-owner test that rejects `(use-package p3-r-tools` and the old `C-c R` binding in `config.org` while asserting ESS load precedes `p3/windows-configure-r-program`.

- [ ] **Step 2: Verify RED**

```bash
emacs -Q --batch -L lisp -l test/p3-config-test.el -f ert-run-tests-batch-and-exit
```

- [ ] **Step 3: Remove the early R-tools configuration stanza**

Delete the existing `use-package p3-r-tools` block and its `C-c R` binding from `* Functions`; leave `p3-core` unchanged.

- [ ] **Step 4: Replace the inline ESS implementation**

Use:

```org
** ESS

ESS package wiring, R-mode hooks, keybindings, buffer defaults, and ESS-specific
Company configuration live in =lisp/p3-config-ess.el=. Project-aware ESS
process/session behavior remains in =lisp/p3-ess.el=, while project templates
and user-facing R workflow commands remain in =lisp/p3-r-tools.el=.

#+BEGIN_SRC emacs-lisp
  (p3/config-load-module 'p3-config-ess)
#+END_SRC

On Windows, select the R executable here, preserving the existing subsystem
startup boundary.

#+BEGIN_SRC emacs-lisp
  (p3/windows-configure-r-program)
#+END_SRC
```

- [ ] **Step 5: Verify no earlier executable R-tools dependency**

```bash
git grep -n "p3-r-\|p3-r-command-map\|p3-r-tools" -- config.org
```

Expected: any match before the ESS section is prose/commentary only.

- [ ] **Step 6: Verify GREEN across affected suites**

```bash
emacs -Q --batch -L lisp -l test/p3-config-loader-test.el -l test/p3-config-test.el -l test/p3-config-ess-test.el -l test/p3-ess-test.el -l test/p3-r-tools-test.el -f ert-run-tests-batch-and-exit
```

- [ ] **Step 7: Commit**

```bash
git add config.org test/p3-config-test.el
git commit -m "Route ESS configuration through its module"
```

---

### Task 4: Wire CI coverage

**Files:**
- Modify: `.github/workflows/emacs-tests.yml`
- Modify: `.github/workflows/windows-platform-tests.yml`

**Interfaces:**
- Consumes: new module/test.
- Produces: Ubuntu compiler/full-suite coverage and Windows source-boundary coverage.

- [ ] **Step 1: Add Ubuntu compile/test entries**

Add `lisp/p3-config-ess.el` to byte compilation and `test/p3-config-ess-test.el` to the ERT load list.

- [ ] **Step 2: Extend Windows path triggers and source tests**

Add triggers for `lisp/p3-config-ess.el`, `lisp/p3-ess.el`, `lisp/p3-r-tools.el`, `test/p3-config-ess-test.el`, `test/p3-ess-test.el`, and `test/p3-r-tools-test.el`. Keep Windows byte compilation limited to existing boundary modules; add only `test/p3-config-ess-test.el` to the Windows config architecture ERT command.

- [ ] **Step 3: Static-check workflow diff**

```bash
git diff --check
git diff -- .github/workflows/emacs-tests.yml .github/workflows/windows-platform-tests.yml
```

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/emacs-tests.yml .github/workflows/windows-platform-tests.yml
git commit -m "Cover ESS configuration boundary in CI"
```

---

### Task 5: Final verification and adversarial review

**Files:** Verify all changed files; do not expand scope.

**Interfaces:** Consumes Tasks 1-4; produces a merge-ready branch, with merge still requiring explicit approval.

- [ ] **Step 1: Check scope and whitespace**

```bash
git diff --check master...HEAD
git diff --stat master...HEAD
```

Only the approved spec/plan plus ESS boundary implementation/tests/workflows may differ.

- [ ] **Step 2: Compare moved forms with `master`**

Compare old inline ESS, Company backend, and inferior-buffer helper forms against `HEAD:lisp/p3-config-ess.el`; reject semantic drift.

- [ ] **Step 3: Run complete local ERT gate if Emacs is available**

Use the Ubuntu CI suite plus `test/p3-config-ess-test.el`; expect zero unexpected failures and only existing environment-dependent skips.

- [ ] **Step 4: Confirm generated artifacts remain ignored/untracked**

```bash
git check-ignore -q config.el
git check-ignore -q lisp/example.elc
test -z "$(git ls-files 'config.el' '*.elc')"
```

- [ ] **Step 5: Push once and verify final PR merge-ref CI**

Ubuntu `Emacs tests` must compile successfully and have zero unexpected ERT failures. Windows `Windows platform tests` must have zero unexpected failures. If CI fails, retrieve the exact job log and fix the root cause without diagnostic machinery or repeated probe pushes.

- [ ] **Step 6: Final rejection-oriented review**

Reject if `p3-ess.el` still owns buffer configuration, generic completion still owns ESS Company state, `p3/ess-setup` is not called explicitly, `p3-r-tools.el` behavior changed, any ESS binding/setting/backend value drifts, Windows R ordering changes, the narrow display rule moves/broadens, the Company bug is mixed in, generated artifacts are tracked, or CI has an unexpected failure.

If none apply, report merge-ready; do not merge without explicit user approval.
