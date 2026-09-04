# Python Configuration Boundary Design

## Goal

Extract Python package wiring and declarative settings from `config.org` into a focused `lisp/p3-config-python.el` module while preserving current Python behavior exactly.

This is a structural refactor only. It does not redesign interpreter selection, virtual-environment handling, basedpyright installation, Eglot usage, REPL behavior, diagnostics ownership, or Python keybindings.

## Current State

Python support is currently split between:

- `lisp/p3-python.el`, which already contains reusable behavior for project interpreter discovery, project-local Python shell configuration, shell display and evaluation helpers, managed basedpyright bootstrap, Eglot startup, and Python-specific Flycheck suppression;
- `config.org`, which owns the `python` package declaration, Python mode hooks and keybindings, `python-ts-mode` routing and bindings, and the `eglot` package declaration;
- the generic Flycheck block in `config.org`, which additionally contains the Python-specific setting `flycheck-python-flake8-executable`.

The main ownership problem is therefore declarative configuration rather than Python workflow behavior.

## Chosen Boundary

### `p3-config-python.el`

`lisp/p3-config-python.el` becomes the single declarative owner for Python support. It will:

1. require the configuration loader and `use-package` support needed by the module;
2. exact-source load `p3-python.el` through `p3/config-load-module`;
3. preserve the existing `use-package python` declaration, including:
   - all current `python-mode-map` bindings;
   - hooks for project interpreter setup, Eglot startup, and Flycheck suppression;
   - `python-indent-guess-indent-offset`;
   - `python-indent-guess-indent-offset-verbose`;
   - platform-specific `python-shell-interpreter`;
   - `python-shell-interpreter-args`;
4. preserve the existing Emacs 29+ `python-ts-mode` routing and wiring, including:
   - the `\.py\'` `auto-mode-alist` entry;
   - the same three hooks used by `python-mode`;
   - the same six source-buffer keybindings used by `python-mode`;
5. preserve the existing `use-package eglot` declaration and bindings;
6. own the Python-specific Flycheck executable setting:
   - `flycheck-python-flake8-executable` remains exactly `"flake8"`.

The module may add `defvar` or `declare-function` forms when required for warnings-as-errors byte compilation without optional packages loaded. Such declarations are compilation aids only and must not alter runtime behavior.

### `p3-python.el`

`lisp/p3-python.el` remains the Python behavior library. Its responsibility stays unchanged:

- find project-local `.venv` or `venv` interpreters;
- configure Python shell interpreter state buffer-locally;
- display/start the Python shell;
- locate the OS-specific managed Python-tools environment;
- bootstrap/reuse managed basedpyright;
- register basedpyright with Eglot and start Eglot;
- send region/paragraph input and advance through source;
- disable Flycheck when Eglot/Flymake owns Python diagnostics.

No behavior function is to be moved out of this file. No function semantics are to change in this PR unless a compiler-only declaration is required.

### `config.org`

The current full Python block is replaced with a short orchestration stanza:

```elisp
(p3/config-load-module 'p3-config-python)
```

The stanza remains in the current Python section and therefore preserves the existing relative startup position between Projectile, Rainbow, and Shell configuration.

`config.org` should no longer contain direct `use-package python` or `use-package eglot` forms, Python mode hook wiring, `python-ts-mode` keybinding setup, or `flycheck-python-flake8-executable`.

### Generic Flycheck configuration

The existing generic Flycheck block remains in `config.org` and keeps:

- global Flycheck enablement;
- the current excluded global modes;
- `flycheck-checker-error-threshold`.

Only the Python-specific `flycheck-python-flake8-executable` setting moves to `p3-config-python.el`.

## Behavior Freeze

The following behavior must remain unchanged:

- `.venv` is preferred over `venv`;
- Linux interpreter candidates remain `.venv/bin/python` then `venv/bin/python`;
- Windows interpreter candidates remain `.venv/Scripts/python.exe` then `venv/Scripts/python.exe`;
- interpreter selection continues to use the shared `p3/project-root` contract;
- selected project interpreter and virtualenv root remain buffer-local;
- the managed tools environment remains OS-specific under `python-tools/linux/` or `python-tools/windows/`;
- existing basedpyright executables are reused without bootstrapping;
- missing basedpyright continues to be installed into the managed tools venv using the current system-Python/bootstrap procedure;
- Eglot continues to register basedpyright for both `python-mode` and `python-ts-mode` with `--stdio`;
- the same Python shell display behavior remains in place;
- `p3/python-send-region-or-paragraph-and-step` retains current region/paragraph evaluation and navigation semantics;
- Flycheck continues to be disabled in Python buffers when Eglot/Flymake diagnostics are used;
- the default shell interpreter remains `python` on Windows and `python3` elsewhere;
- Python shell args remain `-i`;
- Python indentation settings remain unchanged;
- `.py` files continue to use `python-ts-mode` when that mode exists;
- `python-mode` and `python-ts-mode` retain their existing hooks and source-buffer keybindings;
- Eglot rename/code-action/format bindings remain unchanged;
- Flake8 executable selection remains the literal string `"flake8"`.

No new `display-buffer-alist` rule or other window-placement policy is introduced.

## Mode Symmetry Contract

Where the current configuration intentionally treats `python-mode` and `python-ts-mode` the same, the refactor must preserve that symmetry.

Both modes must continue to run:

- `p3/python-setup-project-interpreter`;
- `p3/python-eglot-ensure`;
- `p3/python-disable-flycheck`.

Both source-mode maps must continue to provide equivalent bindings for:

- `C-<return>` -> unbound/nil;
- `S-<return>` -> `python-shell-send-statement`;
- `C-c C-c` -> `p3/python-send-region-or-paragraph-and-step`;
- `C-<up>` -> `backward-paragraph`;
- `C-<down>` -> `forward-paragraph`;
- `C-c C-z` -> `p3/python-display-shell`.

This contract is called out explicitly because asymmetry between the two modes is the most likely silent regression from moving the configuration.

## Loading and Reload Semantics

`p3-config-python.el` must exact-source load `p3-python.el` through `p3/config-load-module`, matching the module-owner pattern established by other configuration modules.

Reloading the configuration should therefore reload current `p3-python.el` source before reapplying declarative Python package configuration.

The refactor must not add package scanning, module registries, autodiscovery, or a second Python configuration owner.

## Testing Strategy

### New configuration-boundary tests

Add `test/p3-config-python-test.el` to parse and verify the new module structurally and semantically.

Tests should assert at minimum:

1. `p3-config-python.el` exact-source loads `p3-python.el`;
2. the `python` declaration preserves the current `python-mode` bindings exactly;
3. the `python-mode` hooks remain exactly the three current Python hooks;
4. Python custom values remain semantically identical:
   - `python-indent-guess-indent-offset t`;
   - `python-indent-guess-indent-offset-verbose nil`;
   - platform-specific `python-shell-interpreter` expression unchanged;
   - `python-shell-interpreter-args "-i"`;
5. `python-ts-mode` retains the conditional `auto-mode-alist` routing, the same three hooks, and the same source-buffer bindings as `python-mode`;
6. the intended `python-mode`/`python-ts-mode` symmetry is asserted directly rather than only checking individual symbol presence;
7. the Eglot declaration preserves:
   - `C-c l r` -> `eglot-rename`;
   - `C-c l a` -> `eglot-code-actions`;
   - `C-c l f` -> `eglot-format`;
8. `flycheck-python-flake8-executable` is set to `"flake8"` in `p3-config-python.el` and is absent from the generic Flycheck block;
9. `config.org` contains one Python configuration owner, `(p3/config-load-module 'p3-config-python)`, and no longer owns direct Python/Eglot package wiring.

### Existing behavior tests

`test/p3-python-test.el` remains the behavioral regression suite for `p3-python.el` and should continue to cover:

- `.venv` preference;
- shared project-root use;
- nested project markers;
- buffer-local interpreter setup;
- Windows venv layout;
- platform-specific tools path;
- reuse of an existing basedpyright server;
- safe Flycheck suppression.

The behavior suite should not be weakened or rewritten merely because configuration ownership moves.

### Architecture tests

Update `test/p3-config-test.el` so its structural expectations reflect the new owner:

- configuration-module count increases from six to seven;
- Python is represented by `(p3/config-load-module 'p3-config-python)` rather than inline `use-package p3-python`, `use-package python`, or `use-package eglot` forms;
- existing startup-order expectations preserve the Python section's current relative location;
- moved Python configuration is asserted absent from `config.org`.

### CI

Add the new module and configuration-boundary tests to the existing Ubuntu and Windows gates.

The warnings-as-errors byte-compile path must not introduce new package-install churn. It should use the existing CI package-install suppression established during the ESS extraction. Built-in `python.el` and Eglot availability may be used where present, but CI must not bootstrap basedpyright merely to compile configuration.

The final gate remains:

- warnings-as-errors byte compilation;
- full Ubuntu ERT suite;
- Windows platform/project tests;
- Windows configuration-architecture tests including the new Python boundary tests.

## Out of Scope

This PR does not:

- replace Eglot;
- change or remove basedpyright;
- change how basedpyright is installed;
- change Python REPL behavior;
- change project interpreter discovery;
- change virtual-environment policy;
- change Flycheck/Flymake diagnostic ownership;
- fix or redesign Company completion;
- introduce Corfu;
- change tree-sitter policy;
- add new Python packages;
- add new window/display behavior;
- change Org Babel Python configuration;
- refactor unrelated Flycheck settings;
- split `p3-python.el` into additional behavior libraries.

Any such change should be a separate bounded or architectural follow-up after this ownership cleanup lands.

## Acceptance Criteria

The refactor is complete when:

1. `p3-config-python.el` is the single declarative Python configuration owner;
2. `p3-python.el` remains the reusable Python behavior owner with unchanged runtime semantics;
3. `config.org` contains only the Python module-loader stanza for this subsystem;
4. the generic Flycheck block no longer owns Python-specific executable configuration;
5. `python-mode` and `python-ts-mode` preserve their current hook and keybinding symmetry;
6. all frozen Python settings and Eglot bindings are semantically unchanged;
7. existing Python behavior tests remain green;
8. new Python configuration-boundary tests pass on the intended CI platforms;
9. no unrelated subsystem, display policy, or package architecture changes are included.
