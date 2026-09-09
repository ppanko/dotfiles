# Project and Session Continuity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement issue #29 so project switching reuses one native Tab Bar workspace per normalized `project.el` root while persistent `recentf` and `save-place` state provide lightweight continuity across restarts.

**Architecture:** Keep `project.el` authoritative. Store only a normalized project-root marker in each project tab's runtime tab alist; reuse that tab when switching, and clear duplicate root markers rather than creating a registry or deleting useful tabs. Wire native `project-switch-project` directly to a resume command through `project-switch-commands`, use `consult-project-buffer` for project re-entry, replace `winner-mode` with `tab-bar-history-mode`, and enable built-in `recentf-mode`/`save-place-mode`. Do not use `desktop.el` or serialized workspace state.

**Tech Stack:** Emacs 29+, built-in `project.el`, `tab-bar`, `recentf`, `saveplace`; Consult; ERT; GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-08-project-session-continuity-design.md`

## Global Constraints

- `project.el` remains the sole filesystem project identity layer.
- One normalized project root maps to at most one active native project tab in a running session.
- Existing project-tab window layouts are preserved when reused.
- `C-x b` remains global `consult-buffer`; `consult-project-buffer` is only the project re-entry surface.
- Persistent state across restarts is limited to `recentf` and `save-place`.
- Do not add `desktop.el`, a project registry, a session database, per-project serialized layouts, or a third-party workspace framework.
- Non-project tabs remain valid and untouched.
- Preserve the current Consult -> `recentf` advice unless equivalent already-open-buffer recency is demonstrated.

---

### Task 1: Specify continuity behavior with failing ERT coverage

**Files:**
- Create: `test/p3-project-continuity-test.el`
- Modify: `.github/workflows/emacs-tests.yml`

**Interfaces:**
- Consumes: existing `p3-project`, `p3-config-project`, `p3-config-base`, `p3-config-workspace` modules.
- Produces: behavioral expectations for `p3/project-normalize-root`, `p3/project-switch-to-tab`, and `p3/project-resume`; configuration expectations for project switching, persistence modes, and tab history.

- [ ] **Step 1: Add a focused ERT file** covering:

```elisp
(ert-deftest p3-continuity-normalizes-equivalent-project-roots () ...)
(ert-deftest p3-continuity-creates-one-project-tab-for-new-root () ...)
(ert-deftest p3-continuity-reuses-project-tab-without-rebuilding-layout () ...)
(ert-deftest p3-continuity-reconciles-duplicate-project-tab-metadata () ...)
(ert-deftest p3-continuity-leaves-non-project-tabs-unclaimed () ...)
(ert-deftest p3-continuity-resume-hands-selected-root-to-consult-project-buffer () ...)
(ert-deftest p3-continuity-config-wires-native-project-switch-to-resume () ...)
(ert-deftest p3-continuity-config-enables-recentf-and-save-place () ...)
(ert-deftest p3-continuity-config-uses-tab-history-not-winner () ...)
(ert-deftest p3-continuity-init-preserves-consult-recentf-recency-advice () ...)
(ert-deftest p3-continuity-does-not-enable-desktop-restore () ...)
```

Use real Tab Bar state for tab identity/reuse tests. Stub only the interactive Consult handoff where invoking a minibuffer would make batch testing impossible.

- [ ] **Step 2: Add the test file to the existing ERT workflow** immediately after `test/p3-project-test.el`.

- [ ] **Step 3: Push the test-only commit and verify RED** through the pull-request workflow. Expected failures are missing continuity functions/configuration, not syntax or fixture errors.

- [ ] **Step 4: Commit**

```bash
git add test/p3-project-continuity-test.el .github/workflows/emacs-tests.yml
git commit -m "test: specify project session continuity"
```

---

### Task 2: Implement runtime project-tab identity and reuse

**Files:**
- Modify: `lisp/p3-project.el`
- Test: `test/p3-project-continuity-test.el`

**Interfaces:**
- Consumes: `project-current`, `project-root`, `tab-bar-tabs`, `tab-bar-tabs-set`, `tab-bar-select-tab`, `tab-new`, `tab-rename`.
- Produces:
  - `(p3/project-normalize-root ROOT) -> canonical directory string or nil`
  - `(p3/project-switch-to-tab ROOT) -> normalized root after selecting/creating its tab`
  - `(p3/project-resume) -> interactive project resume action`

- [ ] **Step 1: Implement root normalization** using `expand-file-name`, `file-truename`, and `file-name-as-directory`, returning nil when the root is not an existing directory.

- [ ] **Step 2: Implement tab lookup/reconciliation** by reading a `p3-project-root` entry from Tab Bar tab alists. Prefer an already-current matching tab when duplicates exist; otherwise prefer the first matching tab. Clear only the duplicate root metadata so useful duplicate layouts survive as ordinary tabs.

- [ ] **Step 3: Implement project-tab selection/creation**. Reuse a matching tab by absolute tab index without changing its windows. If none exists, call `tab-new`, mark the new current tab with the normalized root, and give it a display name derived from the root basename. Never claim a pre-existing non-project tab.

- [ ] **Step 4: Implement `p3/project-resume`**. Resolve the selected `project.el` project, normalize its root, select/create its tab, dynamically bind `project-current-directory-override` to that root, then call `consult-project-buffer` interactively. A missing root must raise an ordinary user-facing error before tab creation.

- [ ] **Step 5: Verify GREEN** with the focused ERT file and then the full ERT suite.

- [ ] **Step 6: Commit**

```bash
git add lisp/p3-project.el test/p3-project-continuity-test.el
git commit -m "feat: add native project tab continuity"
```

---

### Task 3: Wire native project switching and lightweight persistence

**Files:**
- Modify: `lisp/p3-config-project.el`
- Modify: `lisp/p3-config-workspace.el`
- Modify: `lisp/p3-config-base.el`
- Test: `test/p3-project-continuity-test.el`

**Interfaces:**
- Consumes: `p3/project-resume` from Task 2.
- Produces: normal `project-switch-project` dispatch directly to resume; global persistent recency/place state; native per-tab window history.

- [ ] **Step 1: Wire project switching** by requiring `p3-project` and setting `project-switch-commands` to the symbol `p3/project-resume`. This preserves the native `C-x p p` project chooser while replacing the secondary dispatch menu with resume behavior; all other project commands remain on `project-prefix-map`.

- [ ] **Step 2: Enable persistence** in `p3-config-base.el` with built-in `recentf-mode` and `save-place-mode`. Keep persistence file locations at their native `user-emacs-directory` defaults unless the existing config requires otherwise.

- [ ] **Step 3: Replace overlapping window history** in `p3-config-workspace.el`: remove `winner-mode` setup, configure built-in `tab-bar`, enable `tab-bar-mode`, and enable `tab-bar-history-mode`.

- [ ] **Step 4: Keep `init.el` unchanged** unless tests prove the existing Consult -> `recentf` advice conflicts with enabled `recentf-mode`.

- [ ] **Step 5: Verify GREEN** with byte compilation, smoke-load checks, focused ERT, and full ERT.

- [ ] **Step 6: Commit**

```bash
git add lisp/p3-config-project.el lisp/p3-config-workspace.el lisp/p3-config-base.el test/p3-project-continuity-test.el
git commit -m "feat: wire project continuity configuration"
```

---

### Task 4: Final integration, cleanup, and review

**Files:**
- Modify if necessary: `.github/workflows/emacs-tests.yml`
- Delete before merge: `docs/superpowers/plans/2026-09-08-project-session-continuity.md`
- Preserve unchanged: `docs/superpowers/specs/2026-09-08-project-session-continuity-design.md`

**Interfaces:**
- Consumes: all behavior from Tasks 1-3.
- Produces: one reviewable implementation PR for issue #29 without leaving implementation-plan debris in the live tree.

- [ ] **Step 1: Run/observe full CI** and fix only failures caused by this feature.

- [ ] **Step 2: Adversarially verify** that no desktop/session serialization, parallel project registry, custom MRU database, or third-party workspace framework entered the diff.

- [ ] **Step 3: Verify user-facing contracts**: one tab per normalized root, renamed tabs still reuse by metadata, existing layouts survive reuse, non-project tabs remain ordinary, `C-x b` remains global, project switch opens `consult-project-buffer`, restart persistence is only recent files and saved places.

- [ ] **Step 4: Remove this temporary implementation plan** so the working tree keeps only the durable design spec.

- [ ] **Step 5: Commit final cleanup**

```bash
git add -A
git commit -m "docs: remove completed continuity implementation plan"
```

- [ ] **Step 6: Open a PR** titled `Add persistent project and session continuity` with `Closes #29`, implementation summary, and verification results.
