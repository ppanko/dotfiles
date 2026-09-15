# Nonblocking File Visits Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove known synchronous external-tool bootstrap work and redundant project discovery from ordinary R/Python file visits, while caching Windows tool discovery for the Emacs session.

**Architecture:** Keep explicit bootstrap commands responsible for expensive provisioning. File-visit hooks may only use cheap local readiness checks and then start Eglot when tooling is already prepared. Reuse the project root resolved by file-routing through a narrow dynamically scoped visit context rather than a new global project cache, and cache Windows R/Rtools selection behind the existing platform boundary.

**Tech Stack:** Emacs Lisp, ERT, built-in `project.el`, ESS, Python/Eglot, GitHub Actions.

**Spec:** GitHub issue #80, Phase 1.

## Global Constraints

- Preserve existing R/Python editing, REPL, project-tab, modeline, and cross-platform behavior.
- Ordinary file visits must not synchronously install/provision language tooling or run the known heavyweight R validation path.
- Prefer existing explicit `p3/r-bootstrap-language-server` and `p3/python-bootstrap-language-server` commands over background installers.
- Do not add a general project-cache/invalidation framework.
- Windows discovery is cached per Emacs session and remains explicitly refreshable.
- CI guards structural invariants; do not add brittle wall-clock thresholds.

---

### Task 1: Make Python file visits provisioning-free

**Files:**
- Modify: `test/p3-python-test.el`
- Modify: `lisp/p3-python.el`

**Interfaces:**
- Produces: `p3/python-language-server-executable` returns the managed basedpyright executable only when it already exists.
- Keeps: `p3/python-ensure-language-server` as the explicit provisioning path used by `p3/python-bootstrap-language-server`.

- [ ] Write an ERT test that stubs `call-process` to fail, leaves the managed server absent, invokes `p3/python-eglot-ensure`, and asserts no bootstrap process is attempted.
- [ ] Run the test and confirm it fails because `p3/python-eglot-ensure` currently calls `p3/python-ensure-language-server`.
- [ ] Add `p3/python-language-server-executable`; change `p3/python-eglot-ensure` to use only that cheap readiness check. Keep explicit bootstrap behavior unchanged.
- [ ] Run the Python tests and confirm they pass.

### Task 2: Make R file visits validation/provisioning-free

**Files:**
- Modify: `test/p3-r-language-server-test.el`
- Modify: `lisp/p3-r-language-server.el`

**Interfaces:**
- Produces: a small machine-local readiness marker under `r-tools/<platform>/` containing the selected R program and managed library.
- Produces: a cheap readiness lookup used by `p3/r-language-server-command` that checks only local state/filesystem presence.
- Keeps: `p3/r-ensure-language-server` as the explicit heavyweight validation/provisioning path used by `p3/r-bootstrap-language-server`.

- [ ] Write ERT tests proving `p3/r-language-server-command` does not call `p3/r-version`, `p3/r-language-server-installed-p`, or the managed R process when no ready marker exists.
- [ ] Run the test and confirm it fails because the command currently delegates to `p3/r-ensure-language-server`.
- [ ] Add marker read/write helpers and write the marker after successful explicit bootstrap/validation.
- [ ] Change the file-visit command path to consume only valid marker state plus cheap filesystem checks; warn once with the explicit bootstrap command when unavailable.
- [ ] Run R language-server tests and confirm they pass.

### Task 3: Cache Windows R/Rtools discovery

**Files:**
- Modify: `test/p3-platform-test.el`
- Modify: `lisp/p3-platform.el`

**Interfaces:**
- Produces: session caches for `p3/windows-select-rtools` and `p3/windows-select-r-program`, including cached absence.
- Produces: `p3/windows-refresh-tool-discovery` to clear caches and rerun Windows configuration explicitly.

- [ ] Write ERT tests that call each selector twice and assert underlying directory discovery runs once, including the no-result case.
- [ ] Run the tests and confirm repeated calls currently rescan.
- [ ] Add cache sentinels and memoize the two selectors without changing override precedence.
- [ ] Add `p3/windows-refresh-tool-discovery` to clear both caches and reconfigure Windows Rtools/R state.
- [ ] Run platform tests and confirm they pass.

### Task 4: Reuse project identity during routed file visits

**Files:**
- Modify: `test/p3-project-test.el`
- Modify: `test/p3-config-project-test.el` if advice-shape assertions require it
- Modify: `lisp/p3-project.el`
- Modify: `lisp/p3-config-project.el`
- Modify: `lisp/p3-config-appearance.el`

**Interfaces:**
- Produces: `p3/project-with-file-routing`, an around-advice function for displayed file visits.
- Produces: a dynamically scoped visit-root hint consumed by `p3/project-root`; nil is a valid resolved non-project result and therefore must be distinct from the unresolved sentinel.
- Keeps: `p3/project-route-file` as the routing primitive used by already-open buffer routing.

- [ ] Write an ERT test in which routing resolves a project once, the wrapped file-open operation calls `p3/project-root` multiple times, and `project-current` is observed exactly once.
- [ ] Run the test and confirm it fails with the current `:before` routing plus independent lookups.
- [ ] Add the narrow dynamic visit-root hint and around wrapper; switch `find-file`/`find-file-other-window` advice to the wrapper.
- [ ] Change appearance project context to consume `p3/project-root` rather than calling `project-current` directly.
- [ ] Run project/appearance/Python/ESS tests to confirm project semantics remain intact, including General workspace, nested markers, remote files, and Consult preview behavior.

### Task 5: Full verification and PR cleanup

**Files:**
- Remove after implementation: `docs/superpowers/plans/2026-09-15-nonblocking-file-visits.md` (Git history retains the active implementation record; the live roadmap explicitly avoids completed plan archives).

- [ ] Run byte-compilation and the full Linux ERT workflow.
- [ ] Run the Windows platform workflow.
- [ ] Review the final diff for accidental startup/Phase-2 work; keep this PR limited to Phase 1 responsiveness.
- [ ] Confirm no new wall-clock CI thresholds were added.
- [ ] Remove this completed plan from the live tree.
- [ ] Mark the PR ready only when both workflows are green.
