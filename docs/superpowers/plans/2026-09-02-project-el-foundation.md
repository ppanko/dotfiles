# Project.el Foundation Implementation Plan

> **For agentic workers:** use superpowers:executing-plans or superpowers:subagent-driven-development and verify each task before proceeding.

**Goal:** Make built-in `project.el` the single source of P3 project identity while preserving Projectile commands/UI and the existing one-/two-window workflow.

**Spec:** `docs/superpowers/specs/2026-09-02-project-el-foundation-design.md`

## Constraints

- Support Emacs 29+.
- Keep Projectile installed, enabled, and keybound.
- Keep `.projectile` as the project marker in this PR.
- Do not add a custom `project.el` backend or a Projectile fallback.
- Do not change ESS session behavior, terminal placement, Python environment policy beyond shared root identity, or window layout.
- A nested `.projectile` marker intentionally defines an inner P3 project inside an outer VCS repository.
- Python intentionally follows that inner project boundary.
- Native Windows `.projectile` projects must support both root detection and `project-files` enumeration after P3's MSYS2/Rtools path setup.
- Do not merge without explicit approval.

## File map

**Create**

- `lisp/p3-project.el`
- `test/p3-project-test.el`
- `test/p3-project-windows-test.el`

**Modify**

- `init.el`
- `lisp/p3-core.el`
- `lisp/p3-ess.el`
- `lisp/p3-python.el`
- `lisp/p3-r-tools.el`
- `lisp/p3-terminal.el`
- `test/p3-config-test.el`
- `test/p3-core-test.el`
- `test/p3-python-test.el`
- `test/p3-r-tools-test.el`
- `.github/workflows/emacs-tests.yml`
- `.github/workflows/windows-platform-tests.yml`

`config.org` is intentionally **not** modified for project-foundation loading. `p3-project` is a bootstrap dependency and is required from `init.el` before the literate configuration is tangled or loaded.

---

## Task 1: Extract project identity from `p3-core`

- [x] Create `lisp/p3-project.el`.
- [x] Move `p3/project-root` and `p3/use-project-root-as-default-dir` into it.
- [x] Require built-in `project` there.
- [x] Register `.projectile` in `project-vc-extra-root-markers`.
- [x] Make Emacs 29+ explicit by failing clearly if `project-vc-extra-root-markers` is unavailable.
- [x] Remove project discovery from `p3-core.el`.
- [x] Move project tests from `p3-core-test.el` to `p3-project-test.el`.

Core implementation:

```emacs-lisp
(require 'project)

(unless (boundp 'project-vc-extra-root-markers)
  (error "P3 project support requires Emacs 29 or newer"))

(add-to-list 'project-vc-extra-root-markers ".projectile")

(defun p3/project-root ()
  "Return the current built-in `project.el' root, if any."
  (when-let ((project (project-current nil)))
    (project-root project)))
```

Required behavior tests:

1. `p3/project-root` delegates to `project-current`/`project-root`.
2. A `.projectile`-only project is detected from a descendant directory.
3. A nested `.projectile` marker wins over an outer Git root.
4. `p3/use-project-root-as-default-dir` remains buffer-local.

Focused verification:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-project-test.el \
  -l test/p3-core-test.el \
  -f ert-run-tests-batch-and-exit
```

---

## Task 2: Migrate project-aware consumers

- [x] Change `p3-ess.el` to require `p3-project` directly.
- [x] Change `p3-r-tools.el` to require `p3-project` directly.
- [x] Change `p3-terminal.el` to require `p3-project` directly.
- [x] Change `p3-python.el` to require `p3-project` directly.
- [x] Replace Python's separate `p3/project-el-root` path with the shared `p3/project-root` contract.
- [x] Keep R project scaffolding emitting `.projectile`.

The only intended semantic change is Python in nested projects:

```text
outer Git repo/
└── analysis/
    ├── .projectile
    └── .venv/
```

Python must now resolve `analysis/` as the P3 root and select the inner `.venv`.

Focused verification:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-project-test.el \
  -l test/p3-python-test.el \
  -l test/p3-ess-test.el \
  -l test/p3-r-tools-test.el \
  -l test/p3-terminal-test.el \
  -f ert-run-tests-batch-and-exit
```

---

## Task 3: Establish project identity at bootstrap

- [x] Add the P3 Lisp directory to `load-path` in `init.el`.
- [x] Immediately require `p3-project` before calling `p3/load-config`.
- [x] Keep platform setup in `config.org`; do not move Rtools/MSYS2 setup into the project library.
- [x] Add a config regression test proving `p3-project` loads after the Lisp path is established and before the literate config is loaded.

Required ordering:

```emacs-lisp
(defconst p3/lisp-directory
  (expand-file-name "lisp" user-emacs-directory))
(add-to-list 'load-path p3/lisp-directory)
(require 'p3-project)

;; definition of p3/load-config ...
(p3/load-config t)
```

This bootstrap position is intentional: `.projectile` must be registered before any project-aware package can populate `project.el` caches.

---

## Task 4: Prevent Projectile from becoming the `project.el` provider

Projectile's global mode adds `project-projectile` to `project-find-functions`. Leaving that hook in place would make `p3/project-root` indirectly call Projectile even though P3 no longer calls `projectile-project-root` itself.

- [x] Keep `projectile-mode` enabled.
- [x] Add a P3 policy function that removes only `project-projectile` from `project-find-functions`.
- [x] Run that policy once when `p3-project.el` loads.
- [x] Add it to `projectile-mode-hook` so toggling/re-enabling Projectile cannot restore itself as the `project.el` provider.
- [x] Do not advise Projectile internals and do not disable Projectile commands/UI.

Implementation:

```emacs-lisp
(defun p3/project-keep-native-provider ()
  "Keep Projectile from overriding native `project.el' project discovery."
  (remove-hook 'project-find-functions #'project-projectile))

(add-hook 'projectile-mode-hook #'p3/project-keep-native-provider)
(p3/project-keep-native-provider)
```

Regression test requirements:

1. Start with `project-find-functions` containing `project-projectile` ahead of `project-try-vc`.
2. Run `projectile-mode-hook`.
3. Verify `project-projectile` is removed while `project-try-vc` remains.
4. Perform a real `project-current` lookup in a temporary Git repository.
5. Fail the test if `project-projectile` is invoked.

The regression was first introduced without the production fix and verified to fail specifically because `project-projectile` remained in `project-find-functions`. The implementation was added only after that red result.

---

## Task 5: Cross-platform verification

### Ubuntu / Emacs 29

Byte-compile extracted modules with warnings as errors, including `p3-project.el`, then run the full ERT suite including `p3-project-test.el`.

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

Then run the repository ERT suite.

### Native Windows

Extend the existing Windows workflow rather than adding a new workflow.

The Windows gate must:

1. expose a Unix-compatible MSYS2 `find`/`bash` environment to P3 platform setup;
2. byte-compile `p3-platform.el` and `p3-project.el`;
3. create a temporary `.projectile`-only project;
4. confirm `project-current` resolves its root;
5. confirm `project-files` enumerates a file inside it.

The CI fixture may use Git for Windows' bundled MSYS2 tree because the contract under test is the same one P3 relies on from Rtools: `usr/bin/bash.exe` plus a Unix-compatible `find.exe` exposed through the platform setup.

---

## Final review checklist

- [x] `project.el` owns P3 identity.
- [x] Projectile remains available as UI/commands but cannot provide `project-current` results for P3.
- [x] `.projectile` remains supported for old and newly generated projects.
- [x] Nested `.projectile` semantics are explicit and tested.
- [x] Python uses the shared root.
- [x] ESS/R/vterm behavior is otherwise unchanged.
- [x] No new window-management behavior is introduced.
- [x] `config.org` startup/tangling behavior is not redesigned.
- [x] Windows project-file enumeration is covered.
- [x] Final Ubuntu and Windows CI gates green on the reviewed head.
- [ ] Explicit merge approval received.
