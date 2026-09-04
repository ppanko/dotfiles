# Configuration Module Architecture Design

## Status

Design for the third Emacs modernization PR. This PR establishes a durable boundary between top-level configuration orchestration, declarative configuration modules, and reusable behavior libraries. It preserves user-facing behavior and deliberately avoids the later ESS, Python, Org, terminal, or GPTel cleanups.

The only intentional startup-order normalization is that the existing Windows Rtools/MSYS2 activation stage becomes an explicit prerequisite for ordinary configuration modules. Its prerequisites must remain ahead of it: `load-prefer-newer`, auto-compile activation, and `secrets.el` loading stay in the early orchestration layer.

## Problem

`config.org` currently serves several roles at once:

- top-level documentation and orchestration;
- package declarations, settings, hooks, and keybindings;
- reusable interactive commands and helper functions;
- subsystem-specific state and workflow implementation.

Earlier modernization work already moved some behavior into focused libraries such as `p3-project.el`, `p3-python.el`, `p3-ess.el`, `p3-terminal.el`, `p3-gptel.el`, and `p3-org-export.el`. The remaining literate configuration still contains substantial generic implementation alongside package wiring. As a result, `config.org` remains long and mixes architectural levels.

PR #11 deliberately simplified startup around one generated `config.el` cache. Using multi-target Org tangling to create tracked Lisp modules would complicate that model and make the generated cache responsible for source layout. The module architecture therefore uses tracked Lisp files as first-class sources rather than additional tangle outputs.

A second constraint follows from that decision: `C-c r` currently rebuilds and reloads `config.org`. Once configuration moves into tracked modules, reloading only the generated cache is insufficient unless those tracked modules are explicitly re-evaluated.

## Goals

1. Make `config.org` a concise, annotated map of the Emacs configuration.
2. Establish a clear distinction between configuration modules and reusable behavior libraries.
3. Move coherent generic/global configuration out of `config.org` without changing user-facing behavior.
4. Preserve the simple single-cache startup model from PR #11.
5. Preserve useful `C-c r` reload behavior for code moved out of `config.org` in this PR.
6. Keep later subsystem cleanup PRs focused and meaningful.
7. Make the new boundaries independently understandable and testable.

## Non-goals

This PR does not:

- redesign ESS or R behavior;
- redesign Python behavior;
- reorganize Org, Org-roam, presentations, citations, LaTeX, or SQL;
- redesign terminal/vterm or GPTel behavior;
- replace Company or otherwise change completion technology;
- replace Projectile or finish Projectile cleanup;
- broaden `display-buffer-alist` policy;
- change established keybindings without a migration necessity;
- introduce a module registry, autoload framework, package manager, or automatic module discovery;
- convert the repository to multi-target Org tangling;
- redesign the existing shell or R-program platform stages.

## Source-of-truth contract

After this PR, configuration authority is distributed deliberately:

- `init.el` owns bootstrap and startup prerequisites that must exist before `config.org` can load.
- `config.org` is the top-level human-readable configuration map. It owns early orchestration order, explicitly composes enabled configuration modules, and retains still-unmigrated specialized subsystem blocks.
- `lisp/p3-config-*.el` files are authoritative for declarative package configuration in their domains.
- `lisp/p3-*.el` behavior libraries are authoritative for reusable commands, state, process logic, filesystem operations, and workflow implementation.
- generated `config.el` remains an ignored startup cache of `config.org` only.

`config.org` is therefore the top-level source and map, but it is no longer the sole file containing all authoritative configuration.

## Early orchestration contract

A small bootstrap section remains explicit in `config.org` because these settings must precede ordinary configuration modules.

The order is:

1. set `load-prefer-newer`;
2. enable the existing auto-compile behavior;
3. load `secrets.el` if present;
4. load `p3-platform` and run only the existing `p3/windows-configure-rtools` stage;
5. load ordinary `p3-config-*` modules;
6. continue into the still-unmigrated specialized subsystem sections.

This preserves the current machine-local override contract: `secrets.el` may set `p3/windows-rtools-override` before Rtools discovery occurs.

Only Rtools/MSYS2 activation is part of this early platform stage. `p3/windows-configure-r-program` remains with ESS/R configuration, and `p3/windows-configure-shell` remains with the existing shell/terminal area. PR 3 must not pull those later stages forward.

`load-prefer-newer` stays early because ordinary local libraries may still be loaded through `require`; fresh source must not lose to stale bytecode merely because configuration was modularized.

## Dependency direction

The intended dependency direction is one-way:

```text
init.el
  |
  v
config.org
  |
  +--> early orchestration
  |      +--> load-prefer-newer / auto-compile
  |      +--> secrets.el
  |      +--> p3-platform: Rtools/MSYS2 stage only
  |
  +--> p3-config-*
          |
          +--> p3-* behavior libraries
          |
          +--> package configuration
```

Rules:

1. `config.org` explicitly chooses which configuration modules are enabled and their broad loading order.
2. Configuration modules may depend on behavior libraries when they need reusable implementation.
3. Behavior libraries must not depend on `p3-config-*` modules or on `use-package`.
4. Configuration modules should not depend on one another unless a true hard dependency exists. Loading order must not substitute for undocumented coupling.
5. No code scans `lisp/`, builds a module registry, or automatically loads matching filenames.
6. Early orchestration is not itself turned into another configuration module.

## Exact source loading and reload contract

The new tracked configuration modules must be loaded from their exact `.el` source files, not merely `require`d as already-provided features.

`p3-config-loader.el` should therefore expose one small explicit source-loading helper for tracked local modules. Its responsibilities are limited to:

- resolve a named local module under `lisp/`;
- load that exact `.el` file with `load-file`;
- fail normally if the file is missing or invalid.

It must not discover modules, maintain a registry, scan directories, or create another cache.

For migrated domains, `config.org` should use this helper directly, for example:

```org
* Completion
Vertico, Orderless, Consult, and related packages provide minibuffer
completion and search.

#+begin_src emacs-lisp
(p3/config-load-module 'p3-config-completion)
#+end_src
```

Because `load-file` re-evaluates the source even when its feature is already present, both normal startup and `p3/config-reload` execute the current tracked module source.

The two new behavior libraries are extracted from code that is currently inline in `config.org`, so their edits must also remain visible to `C-c r` in this PR:

- `p3-config-base.el` force-loads the exact source for `p3-commands.el` before wiring commands from it;
- `p3-config-git.el` force-loads the exact source for `p3-git.el` before wiring Git commands from it.

Other existing specialized behavior libraries retain their current reload semantics until their dedicated cleanup phases. PR 3 does not broaden `C-c r` into a general recursive reload system.

## `config.org` end state

For migrated domains, `config.org` should contain:

- a short heading;
- one or two sentences explaining the subsystem's role;
- one explicit source-loader stanza.

The literate file should not duplicate package lists, detailed keybinding inventories, or implementation notes already represented by module source or the keybinding atlas.

## Configuration modules introduced in PR 3

### `p3-config-base.el`

Owns broad global infrastructure that is not editing behavior or a specialized workflow:

- dashboard;
- which-key wiring;
- package-update UI wiring;
- fonts and cursor defaults;
- global process/session defaults such as prompt and Comint behavior;
- backups and auto-save locations;
- global modes such as auto-revert and font lock;
- line-number setup;
- trash behavior;
- async and basic Dired configuration.

It does not own `load-prefer-newer`, auto-compile activation, secrets loading, or platform activation; those remain in the early orchestration section because their order is significant.

It force-loads `p3-commands.el` so commands extracted from formerly inline config remain reloadable with `C-c r`.

Editing semantics such as CUA, delete-selection, whitespace cleanup, indentation, pairing, and editing keybindings belong in `p3-config-editing.el`.

### `p3-config-completion.el`

Owns minibuffer and in-buffer completion wiring:

- savehist;
- Vertico;
- Orderless;
- Marginalia;
- Consult;
- Embark;
- Company;
- small completion-specific helper commands used only to configure or expose those packages.

This PR does not replace Company or redesign completion behavior.

### `p3-config-editing.el`

Owns generic editing package configuration and global editing semantics:

- CUA and delete-selection behavior;
- whitespace cleanup and indentation defaults;
- smartparens;
- undo-tree;
- super-save;
- multiple-cursors;
- generic editing keybindings and hooks that are not tied to a specialized subsystem.

Reusable editing commands with meaningful logic belong in `p3-commands.el`, not this module.

### `p3-config-git.el`

Owns Git package wiring:

- Magit declaration and bindings;
- Magit command-prefix map;
- git-gutter configuration;
- binding/configuration for the config-and-notes synchronization command.

It force-loads `p3-git.el` so Git behavior extracted from formerly inline config remains reloadable with `C-c r`.

### `p3-config-workspace.el`

Owns generic buffer/window/navigation configuration:

- ace-window;
- winner;
- transpose-frame;
- Avy;
- buffer/window package wiring and bindings;
- the existing narrow `inferior-ess-r-mode` display rule.

The name `workspace` is deliberate: `windows` would be ambiguous with Microsoft Windows platform support in `p3-platform.el`.

The ESS display rule remains here for this PR because it is display policy, not ESS process behavior. It must not be broadened into a generic REPL or side-window policy.

## Behavior libraries introduced in PR 3

### `p3-commands.el`

The move set is closed for this PR. It contains these currently-inline definitions and their directly associated data:

- `p3/keybinding-sections`;
- `p3/keybinding-atlas`;
- `p3/save-kill-other-buffers`;
- `p3/sudo-edit`;
- `p3/region-suffix`;
- `p3/newline-after-comma-or-space`;
- `p3/force-quotes`;
- `p3/byte-compile-init-dir`;
- `p3/windows-shell`;
- `move-line`;
- `move-line-up`;
- `move-line-down`;
- `p3/open-in-external-app`;
- `check-curl-version`;
- `p3/get-local-buffer-mode`;
- `p3/is-current-buffer-mode-inferior-ess-r-mode`.

No additional generic helper is pulled into `p3-commands.el` during implementation merely because it looks similar. If another function appears to belong there, it is left for a later cleanup unless moving it is necessary to make one of the listed moves compile or preserve behavior.

Small configuration-only helpers such as prompt advice, process-kill prompt glue, line-number setup, and completion-specific wrapper commands may remain in their owning `p3-config-*` modules.

### `p3-git.el`

Owns the currently-inline reusable Git/process behavior:

- `p3/check-git-installed`;
- `p3/get-commit-message`;
- `p3/git-call`;
- `p3/git-run`;
- `p3/git-commit-and-push-repository`;
- `p3/git-commit-and-push-emacs-config`;
- `close-magit-buffers`.

It must not configure Magit, bind keys, or depend on `use-package`.

Existing function names are preserved in this PR, including legacy unprefixed names. Renaming is unrelated cleanup.

## Extraction rule

A configuration block moves in PR 3 only when all of the following are true:

1. it belongs to one of the five agreed generic/global domains;
2. moving it does not require redesigning a specialized subsystem;
3. its current user-facing behavior can be preserved directly;
4. the destination makes ownership clearer rather than merely shortening `config.org`.

For behavior functions, the explicit lists above are the implementation boundary. This is not a maximum-extraction exercise.

## Configuration-module versus behavior-library rule

`p3-config-*` modules may contain:

- `use-package` declarations;
- package variables and declarative settings;
- hooks and keybindings;
- small glue lambdas whose only purpose is package wiring;
- small package-specific helper functions;
- small command maps that primarily expose package commands.

Substantial reusable functions, process logic, state machines, filesystem or Git operations, nontrivial transformations, and workflow commands belong in `p3-*` behavior libraries.

This rule is an architectural invariant, not a line-count threshold.

## Areas deliberately left for later PRs

The following remain substantially in their current form until their dedicated modernization passes:

- ESS and R runtime/configuration;
- Python;
- terminal/vterm;
- GPTel;
- Org core;
- Org-roam;
- Org presentation;
- citations and BibTeX;
- LaTeX;
- SQL/MySQL;
- Projectile cleanup;
- specialized package blocks tightly coupled to those areas;
- Windows R-program selection and shell configuration beyond preserving their current placement.

Existing focused behavior libraries for those subsystems remain in use. PR 3 does not pull their package configuration into new `p3-config-*` modules prematurely.

## Migration strategy

Migrate one domain at a time. For each domain:

1. add or extend focused tests before moving behavior where practical;
2. create the destination module/library;
3. move code without opportunistic cleanup or behavior changes;
4. replace corresponding `config.org` content with concise orchestration prose and exact source-loader stanzas;
5. run narrow relevant tests;
6. proceed only after the prior move is stable.

Preserve existing command names and keybindings. Compatibility aliases are preferable to unrelated renaming if a technical move requires one.

The early orchestration ordering should be changed as one explicit, reviewable step rather than emerging accidentally from module extraction.

## Testing and verification

### Byte compilation

Every new tracked Lisp module must byte-compile with warnings treated as errors in the Ubuntu gate.

The Windows gate should cover new modules where they participate in existing platform-sensitive startup or tests, but this PR should not create a second broad Windows CI suite solely for organizational refactoring.

### ERT

Focused ERT coverage should include:

- exact-source local module loading even when the feature is already provided;
- `p3/config-reload` picking up edits to a migrated `p3-config-*` module;
- reload picking up edits to `p3-commands.el` and `p3-git.el` through their owning config modules;
- deterministic behavior for `p3-git.el` helpers;
- generic command behavior where practical.

Existing focused module tests remain intact. The full ERT suite remains the final regression gate.

### Structural tests

Repository/config tests should verify:

- `load-prefer-newer` appears before ordinary local configuration-module loading;
- secrets loading appears before `p3/windows-configure-rtools`;
- the early platform stage calls `p3/windows-configure-rtools` but does not pull `p3/windows-configure-r-program` or `p3/windows-configure-shell` forward;
- Rtools activation appears before ordinary `p3-config-*` loading;
- `config.org` explicitly source-loads all five new `p3-config-*` modules;
- listed moved implementation functions no longer exist inline in `config.org`;
- behavior libraries do not require configuration modules;
- the generated startup cache contract remains unchanged;
- generated `config.el` remains ignored and untracked.

Structural tests should enforce meaningful boundaries, not exact formatting or line counts.

### Stale-bytecode regression

At least one test must exercise the relevant source-selection contract: fresh local source must win over stale bytecode for a local dependency loaded after early `load-prefer-newer` is established. The exact `p3-config-*` source loader itself uses `load-file`, so it must always execute the tracked `.el` source directly.

## Behavioral invariants

PR 3 must preserve:

- current one- and two-window workflows;
- the existing narrow ESS display rule exactly, without generalization;
- current completion stack and Company behavior;
- current Magit and Git helper keybindings;
- current generic editing bindings;
- machine-local Rtools overrides from `secrets.el`;
- Windows Rtools/MSYS2 discovery and configuration logic;
- current placement of Windows R-program selection and shell configuration;
- useful `C-c r` reload semantics for all code newly moved out of `config.org` in this PR;
- the single generated `config.el` cache model;
- `config.org` as a readable top-level map;
- existing specialized subsystem behavior.

The deliberate exception to strict execution-order preservation is limited to moving the existing Rtools/MSYS2 activation stage ahead of ordinary configuration modules. Its prerequisites remain ahead of it.

## Failure handling

A module load or configuration error should fail normally and visibly during config loading. PR 3 does not add fallback loaders, partial-module recovery, automatic dependency resolution, recursive module reload, or a second configuration cache.

The existing PR #11 cache contract remains responsible only for deciding whether `config.org` itself needs to be regenerated before load. The new exact-source helper only loads named tracked local source files.

## Expected repository shape

After PR 3, the relevant layout should look approximately like:

```text
init.el
config.org
lisp/
  p3-config-loader.el
  p3-config-base.el
  p3-config-completion.el
  p3-config-editing.el
  p3-config-git.el
  p3-config-workspace.el
  p3-commands.el
  p3-git.el
  p3-core.el
  p3-project.el
  p3-platform.el
  p3-ess.el
  p3-python.el
  p3-r-tools.el
  p3-terminal.el
  p3-gptel.el
  p3-org-export.el
```

This is not a target for one file per `config.org` heading. New modules exist only where they represent the agreed stable conceptual boundaries.

## Acceptance criteria

PR 3 is complete when:

1. the five agreed `p3-config-*` domains are tracked modules;
2. the explicitly listed generic commands and Git behavior have moved into `p3-commands.el` and `p3-git.el`;
3. `config.org` is materially shorter and reads primarily as a configuration map for migrated domains;
4. early orchestration is `load-prefer-newer` / auto-compile, then secrets, then the existing Rtools/MSYS2 activation stage, then ordinary configuration modules;
5. Windows R-program and shell configuration remain in their existing later subsystem areas;
6. migrated configuration modules are exact-source loaded and re-evaluated by `p3/config-reload`;
7. edits to `p3-commands.el` and `p3-git.el` are also picked up by `p3/config-reload`;
8. fresh local source wins over stale bytecode where ordinary `require` remains in use;
9. no specialized later-phase subsystem is substantially redesigned;
10. existing user-facing behavior and keybindings are preserved;
11. all new modules byte-compile cleanly;
12. focused tests and the full regression suite pass;
13. structural tests protect the new boundary and startup ordering;
14. startup still uses one ignored, fingerprint-validated `config.el` cache and no multi-target tangling.
