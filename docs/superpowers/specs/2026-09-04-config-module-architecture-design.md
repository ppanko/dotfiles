# Configuration Module Architecture Design

## Status

Design for the third Emacs modernization PR. This PR establishes a durable boundary between top-level configuration orchestration, declarative configuration modules, and reusable behavior libraries. It is intentionally behavior-preserving and does not perform the later ESS, Python, Org, terminal, or GPTel cleanups.

## Problem

`config.org` currently serves several roles at once:

- top-level documentation and orchestration;
- package declarations, settings, hooks, and keybindings;
- reusable interactive commands and helper functions;
- subsystem-specific state and workflow implementation.

Earlier modernization work already moved some behavior into focused libraries such as `p3-project.el`, `p3-python.el`, `p3-ess.el`, `p3-terminal.el`, `p3-gptel.el`, and `p3-org-export.el`. The remaining literate configuration still contains substantial generic implementation alongside package wiring. As a result, `config.org` remains long and mixes architectural levels.

PR #11 also deliberately simplified startup around one generated `config.el` cache. Using multi-target Org tangling to create tracked Lisp modules would complicate that model and make the generated cache responsible for source layout. The module architecture therefore needs tracked Lisp files as first-class sources rather than additional tangle outputs.

## Goals

1. Make `config.org` a concise, annotated map of the Emacs configuration.
2. Establish a clear distinction between configuration modules and reusable behavior libraries.
3. Move coherent generic/global configuration out of `config.org` without changing behavior.
4. Preserve the simple single-cache startup model from PR #11.
5. Keep later subsystem cleanup PRs focused and meaningful.
6. Make the new boundaries independently understandable and testable.

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
- convert the repository to multi-target Org tangling.

## Source-of-truth contract

After this PR, configuration authority is distributed deliberately:

- `init.el` owns bootstrap and startup prerequisites.
- `config.org` is the top-level human-readable configuration map and explicitly composes enabled configuration modules and still-unmigrated specialized subsystem blocks.
- `lisp/p3-config-*.el` files are authoritative for declarative package configuration in their domains.
- `lisp/p3-*.el` behavior libraries are authoritative for reusable commands, state, process logic, filesystem operations, and workflow implementation.
- generated `config.el` remains an ignored startup cache of `config.org` only.

`config.org` is therefore the top-level source and map, but it is no longer the sole file containing all authoritative configuration.

## Dependency direction

The intended dependency direction is one-way:

```text
init.el
  |
  v
config.org
  |
  +--> early p3-platform setup
  |
  +--> p3-config-*
          |
          +--> p3-* behavior libraries
          |
          +--> package configuration
```

Rules:

1. `config.org` explicitly chooses which configuration modules are enabled and their broad loading order.
2. Configuration modules may `require` behavior libraries when they need reusable implementation.
3. Behavior libraries must not depend on `p3-config-*` modules or on `use-package`.
4. Configuration modules should not depend on one another unless a true hard dependency exists. Loading order must not substitute for undocumented coupling.
5. No code scans `lisp/`, builds a module registry, or automatically loads matching filenames.
6. Platform setup remains explicit and early in `config.org` because it affects PATH, Rtools/MSYS2, Git, shells, and subprocess discovery before ordinary package configuration.

## `config.org` end state

For migrated domains, `config.org` should contain:

- a short heading;
- one or two sentences explaining the subsystem's role;
- one explicit loader stanza.

Example:

```org
* Completion
Vertico, Orderless, Consult, and related packages provide minibuffer
completion and search.

#+begin_src emacs-lisp
(use-package p3-config-completion
  :ensure nil
  :demand t)
#+end_src
```

The literate file should not duplicate package lists, detailed keybinding inventories, or implementation notes already represented by the module source or the keybinding atlas.

## Configuration modules introduced in PR 3

### `p3-config-base.el`

Owns broad startup-adjacent and global configuration that is not a specialized workflow implementation:

- dashboard;
- which-key and the configuration of the keybinding atlas entry point;
- package-update UI wiring;
- auto-compile and `load-prefer-newer`;
- secrets loading;
- fonts and cursor defaults;
- global editing/process defaults that do not belong to a specialized subsystem;
- backups and auto-save locations;
- global modes such as auto-revert and font lock;
- line-number setup;
- trash behavior;
- async and basic Dired configuration.

Platform activation itself stays explicit in `config.org` rather than being hidden inside this module.

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

Owns generic editing package configuration and global editing bindings:

- smartparens;
- undo-tree;
- super-save;
- multiple-cursors;
- whitespace and indentation defaults;
- generic editing keybindings and hooks that are not tied to a specialized subsystem.

Reusable editing commands with meaningful logic belong in `p3-commands.el`, not this module.

### `p3-config-git.el`

Owns Git package wiring:

- Magit declaration and bindings;
- Magit command-prefix map;
- git-gutter configuration;
- binding/configuration for the config-and-notes synchronization command.

Git subprocess and synchronization implementation belongs in `p3-git.el`.

### `p3-config-workspace.el`

Owns generic buffer/window/navigation configuration:

- ace-window;
- winner;
- transpose-frame;
- Avy;
- generic buffer/window helper wiring;
- the existing narrow `inferior-ess-r-mode` display rule.

The name `workspace` is deliberate: `windows` would be ambiguous with Microsoft Windows platform support in `p3-platform.el`.

The ESS display rule remains here for this PR because it is display policy, not ESS process behavior. It must not be broadened into a generic REPL or side-window policy.

## Behavior libraries introduced in PR 3

### `p3-commands.el`

Owns generic reusable interactive commands currently embedded in `config.org`, including coherent helpers such as:

- save/kill-other-buffers;
- sudo edit;
- region suffix/transform helpers;
- newline-after-comma-or-space;
- force-quotes;
- move-line helpers;
- open in external application;
- byte-compile configuration directory;
- curl-version inspection;
- similar generic commands that are not package configuration.

The exact move set should be driven by coherence rather than extracting every inline `defun` mechanically.

### `p3-git.el`

Owns reusable Git/process behavior:

- Git executable validation;
- commit-message generation;
- `process-file` wrappers and error handling;
- repository stage/commit/push workflow;
- config-and-notes synchronization behavior.

It must not configure Magit, bind keys, or depend on `use-package`.

## Extraction rule

A block moves in PR 3 when all of the following are true:

1. it belongs to a generic/global domain covered by the modules above;
2. moving it does not require redesigning a specialized subsystem;
3. its current behavior can be preserved directly;
4. the destination makes the ownership clearer rather than merely shortening `config.org`.

A block stays in `config.org` when extraction would require simultaneous subsystem redesign or when its meaning is clearer next to a later dedicated cleanup area.

This is not a maximum-extraction exercise. Small `setq` forms do not move merely because they are technically generic.

## Configuration-module versus behavior-library rule

`p3-config-*` modules may contain:

- `use-package` declarations;
- package variables and declarative settings;
- hooks and keybindings;
- small glue lambdas whose only purpose is package wiring;
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
- specialized package blocks tightly coupled to those areas.

Existing focused behavior libraries for those subsystems remain in use; PR 3 does not pull their package configuration into new `p3-config-*` modules prematurely.

## Migration strategy

Migrate one domain at a time. For each domain:

1. add or extend focused tests before moving behavior where practical;
2. create the destination module/library;
3. move code without opportunistic cleanup or behavior changes;
4. replace the corresponding `config.org` content with concise orchestration prose and loader stanzas;
5. run the narrow relevant tests;
6. proceed to the next domain only after the prior move is stable.

The migration should preserve existing command names and keybindings unless retaining a name would make the new boundary technically incorrect. Compatibility aliases are preferable to unrelated renaming in this PR.

## Testing and verification

### Byte compilation

Every new tracked Lisp module must byte-compile with warnings treated as errors in the Ubuntu gate.

The Windows gate should cover new modules where they participate in existing platform-sensitive startup or tests, but this PR should not create a second broad Windows CI suite solely for organizational refactoring.

### ERT

Focused ERT coverage should be added for reusable behavior libraries, especially `p3-git.el` and generic commands where behavior can be tested deterministically.

Existing focused module tests remain intact.

The full ERT suite remains the final regression gate.

### Structural tests

Repository/config tests should verify architectural facts such as:

- `config.org` explicitly loads the new `p3-config-*` modules;
- representative moved implementation functions no longer exist inline in `config.org`;
- behavior libraries do not require configuration modules;
- the generated startup cache contract remains unchanged;
- generated `config.el` remains ignored and untracked.

Structural tests should enforce meaningful boundaries, not exact formatting or line counts.

## Behavioral invariants

PR 3 must preserve:

- current one- and two-window workflows;
- the existing narrow ESS display rule exactly, without generalization;
- current completion stack and Company behavior;
- current Magit and Git helper keybindings;
- current generic editing bindings;
- Windows Rtools/MSYS2 platform setup and ordering;
- the single generated `config.el` cache model;
- `config.org` as a readable top-level map;
- existing specialized subsystem behavior.

## Failure handling

A module load or configuration error should fail normally and visibly during config loading. PR 3 does not add fallback loaders, partial-module recovery, automatic dependency resolution, or a second configuration cache.

The existing PR #11 cache contract remains responsible only for deciding whether `config.org` itself needs to be regenerated before load.

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

This is not a target for one file per `config.org` heading. New modules should exist only where they represent stable conceptual boundaries.

## Acceptance criteria

PR 3 is complete when:

1. the five agreed `p3-config-*` domains are tracked modules;
2. generic reusable commands and Git behavior have moved into behavior libraries;
3. `config.org` is materially shorter and reads primarily as a configuration map for migrated domains;
4. platform setup remains explicit and early;
5. no specialized later-phase subsystem has been substantially redesigned;
6. existing behavior and keybindings are preserved;
7. all new modules byte-compile cleanly;
8. focused tests and the full regression suite pass;
9. structural tests protect the new boundary;
10. startup still uses one ignored, fingerprint-validated `config.el` cache and no multi-target tangling.
