# ESS Configuration Boundary Design

## Goal

Finish the ESS portion of the configuration-module migration without changing the user's R/ESS workflow.

After this change, declarative ESS/R-mode configuration belongs in `p3-config-ess.el`, project-aware ESS process behavior remains in `p3-ess.el`, and user-facing R workflow commands remain in `p3-r-tools.el`. `config.org` becomes a short orchestration layer for the subsystem.

This is an extraction/refactoring PR. It does not redesign ESS behavior.

## Current problem

The ESS subsystem is split across four places:

- `config.org` contains the full `ess-r-mode` package declaration, hooks, keybindings, ESS variables, font-lock configuration, linting settings, R startup arguments, and the `compile-rmd` hook helper.
- `p3-ess.el` contains project/session/process ownership behavior.
- `p3-r-tools.el` contains R project/template commands plus user-facing commands that send code through ESS.
- `p3-config-completion.el` contains ESS-specific Company backend state and `p3/ess-company-config` even though that module is intended to own generic completion configuration.

The result is a clear remaining violation of the architecture established by the configuration-module PR: generic completion owns subsystem-specific ESS wiring, while `config.org` still contains a large specialized implementation block.

## Design principles

1. Preserve behavior. Move existing configuration essentially verbatim before considering cleanup.
2. Organize by responsibility, not by whether a function happens to call ESS.
3. Keep the file count flat. Do not create a separate `p3-r-ess.el` or other new behavior layer.
4. Keep configuration modules declarative. Stateful project/process behavior remains outside `p3-config-*`.
5. Keep the existing Windows startup boundary visible in `config.org`.
6. Do not use this refactor to fix the current `company-dabbrev` compatibility error.
7. Do not add module registries, automatic discovery, generalized reload machinery, or broad display policies.

## Ownership after the change

### `p3-config-ess.el`

New tracked configuration module. It owns ESS/R-mode configuration and glue:

- loading/configuring `p3-ess`;
- loading `p3-r-tools` so R workflow bindings have an explicit dependency rather than relying on unrelated source ordering;
- the existing global `C-c R` binding for `p3-r-command-map`;
- the current `use-package ess-r-mode` declaration;
- ESS hooks;
- ESS and inferior-ESS keybindings;
- `ess-ask-for-ess-directory`;
- `ess-style`;
- `ess-eval-visibly`;
- `ess-toggle-underscore`;
- `ess-use-flymake`;
- `flycheck-lintr-linters`;
- `ess--command-default-timeout`;
- `inferior-R-args`;
- `ess-R-font-lock-keywords`;
- `ess-gen-proc-buffer-name-function`;
- the underscore syntax hook currently attached to `ess-mode`;
- `p3/r-company-backends`;
- `p3/ess-company-config`;
- `compile-rmd` and its existing `ess-mode-hook` / `markdown-mode-hook` wiring.

The moved forms should remain semantically equivalent to their current versions. The PR must not opportunistically rename commands, change keybindings, alter values, simplify font-lock, change lint rules, or replace anonymous hooks merely for style.

`p3-config-ess.el` may use `p3/config-load-module` to load `p3-ess` and `p3-r-tools`, matching the exact-source reload pattern already used by the other `p3-config-*` modules.

### `p3-ess.el`

Retains project/session/process ownership only:

- project-root cache;
- project-root to ESS process map;
- process liveness checks;
- registration of inferior processes;
- lazy project-specific R startup;
- assignment of `ess-local-process-name`;
- inferior ESS buffer setup currently implemented there;
- guarded installation of advice around ESS process selection;
- `p3/ess-setup`.

No process/session redesign belongs in this PR.

### `p3-r-tools.el`

Retains user-facing R workflow behavior:

- project scaffolding and templates;
- R document/header/chunk helpers;
- Targets commands;
- Shiny command;
- `view_df` loading/viewing;
- library/setup-section evaluation;
- write-to-read conversion;
- R script archiving;
- helper-file navigation;
- `p3-r-command-map`;
- existing compatibility aliases.

Some of these commands use a live ESS process. That does not make them ESS session-management code. They remain together because they form one coherent user-facing R workflow.

No internal split of `p3-r-tools.el` is required in this PR.

### `p3-config-completion.el`

Becomes generic completion configuration only.

Remove:

- `p3/r-company-backends`;
- `p3/ess-company-config`;
- any declarations present solely for that ESS-specific wiring.

Do not otherwise change the Company package configuration. In particular, do not change Company backends or attempt to fix the current `company-dabbrev` error in this PR.

### `config.org`

The ESS section becomes an orchestration/map section rather than an implementation block.

It should:

1. briefly describe the ownership split;
2. exact-source load `p3-config-ess` using `p3/config-load-module`;
3. retain `p3/windows-configure-r-program` immediately after the ESS configuration stanza.

The standalone `p3-r-tools` loading/binding stanza elsewhere in `config.org` should be removed once `p3-config-ess.el` explicitly owns that configuration dependency and binding.

The Windows R executable selection remains in `config.org` because its startup position is intentional and was explicitly preserved by the previous module-architecture design.

## Dependency direction

The intended dependency shape is:

```text
config.org
  |
  +-- p3-config-ess
  |     +-- p3-ess
  |     |     +-- p3-project
  |     +-- p3-r-tools
  |           +-- p3-project
  |
  +-- p3/windows-configure-r-program
```

`p3-config-ess.el` must not require another `p3-config-*` module. In particular, it must not depend on `p3-config-completion.el`; it only defines the ESS-specific Company backend data and hook function. The generic Company package remains configured by the completion module.

## Loading and reload behavior

`config.org` should use:

```elisp
(p3/config-load-module 'p3-config-ess)
```

The new configuration module should exact-source load its local behavior dependencies so that `C-c r` re-evaluates their current source consistently with the existing configuration-module pattern.

This preserves the current meaning of reload: source is re-evaluated. It does not promise reconciliation of already-bound `defvar` values or arbitrary package state; that general inherited limitation remains outside this PR.

## `compile-rmd`

Keep `compile-rmd` as configuration glue in `p3-config-ess.el`.

Its existing behavior remains unchanged:

- set a buffer-local `compile-command` that renders the current file through `rmarkdown::render()`;
- attach the helper to `ess-mode-hook`;
- attach the same helper to `markdown-mode-hook`.

Do not move it into `p3-r-tools.el`: it configures buffer behavior rather than representing a reusable interactive R workflow command.

Do not rename it in this PR.

## Company boundary

ESS-specific Company configuration moves from `p3-config-completion.el` to `p3-config-ess.el` unchanged.

This refactor deliberately separates ownership from bug fixing. The known Company error:

```text
Company: backend company-dabbrev error "Wrong number of arguments: (2 . 2), 1"
```

is explicitly out of scope. Once this PR is merged, that compatibility issue can be addressed as a small bounded change against the now-correct ESS owner.

## Behavior that must not change

The PR must preserve:

- project-aware ESS process selection;
- lazy R process creation;
- process registration by project root;
- `C-c R` R workflow prefix;
- ESS `S-RET` evaluation behavior;
- `C-.` pipe insertion in ESS buffers;
- `C-c i`, `C-c v`, `C-c m`, `C-c d`, and `C-c l` bindings;
- corresponding inferior-ESS bindings;
- `p3-r-post-run` / `view_df` helper loading behavior (currently `p3-r-load-view-data-frame` on `ess-r-post-run`);
- project-root `default-directory` setup in ESS R buffers;
- underscore word-syntax behavior;
- Company backend contents;
- R indentation style;
- visible evaluation setting;
- ESS Flymake disablement;
- Lintr configuration;
- ESS command timeout;
- `--no-save` R startup argument;
- font-lock keyword configuration;
- ESS process buffer naming;
- Windows R executable selection timing;
- `compile-rmd` behavior and hooks;
- the existing narrow `inferior-ess-r-mode` display rule in `p3-config-workspace.el`.

The display rule is not part of the ESS extraction and must not move or broaden.

## Out of scope

Do not include:

- Company -> Corfu migration;
- Company backend compatibility fixes;
- changes to Company backend composition;
- ESS process/session redesign;
- changes to R startup arguments;
- changes to Lintr/Flycheck policy;
- changes to ESS font-lock;
- changes to project identity;
- changes to `p3-r-tools` public commands;
- splitting `p3-r-tools.el` into multiple files;
- changes to the narrow ESS side-window rule;
- generalized REPL/window placement;
- Projectile cleanup;
- Python cleanup;
- Org cleanup;
- terminal cleanup;
- keybinding redesign;
- package-manager changes.

## Testing strategy

### Existing behavior tests

Keep and run the existing focused suites:

- `test/p3-ess-test.el` for project/session/process semantics;
- `test/p3-r-tools-test.el` for templates, project generation, command-map exposure, and representative ESS-backed R workflow behavior.

These files remain the primary behavioral protection for the two existing libraries.

### New configuration-boundary coverage

Add focused coverage for the new ownership boundary. The tests should verify at minimum:

- `config.org` exact-source loads `p3-config-ess`;
- `config.org` no longer contains the full `use-package ess-r-mode` implementation block;
- `p3/windows-configure-r-program` remains after the ESS module load;
- `p3-config-completion.el` no longer contains `p3/r-company-backends` or `p3/ess-company-config`;
- `p3-config-ess.el` contains the ESS-specific Company definitions;
- `p3-config-ess.el` owns the current ESS hooks and keybindings;
- `p3-config-ess.el` owns `compile-rmd` and both current hooks;
- `p3-config-ess.el` explicitly loads/configures `p3-ess` and `p3-r-tools`;
- the narrow ESS display policy remains in `p3-config-workspace.el` and is not duplicated in the new module.

Because CI does not install/load every optional third-party package in a normal interactive session, boundary tests may inspect the tracked source structurally rather than requiring the complete `p3-config-ess.el` module at test runtime. Behavioral code remains covered by the existing `p3-ess` and `p3-r-tools` tests.

### Compilation and CI

- Byte-compile `p3-config-ess.el` with warnings treated as errors in the Ubuntu workflow.
- Keep the full ERT suite as the primary regression gate.
- Extend Windows coverage when the files changed affect the existing Windows platform/config boundary. At minimum, the structural configuration tests must continue to cover Windows R-program ordering.
- Do not use CI as an iterative diagnostic loop. Batch likely compiler-declaration fixes before rerunning the final gates.

## Acceptance criteria

The PR is complete when:

1. `p3-config-ess.el` exists and owns all declarative ESS/R-mode configuration described above.
2. `p3-ess.el` still contains only project/session/process behavior and has no intentional semantic changes.
3. `p3-r-tools.el` retains the existing R workflow and has no intentional semantic changes.
4. `p3-config-completion.el` contains no ESS-specific Company state or hook function.
5. `config.org` contains a concise ESS orchestration stanza rather than the current large implementation block.
6. Windows R executable selection remains immediately after ESS configuration in the orchestration layer.
7. Existing ESS/R keybindings and configuration values are unchanged.
8. The existing narrow ESS display policy remains unchanged in `p3-config-workspace.el`.
9. The Company `company-dabbrev` error is not addressed in this PR.
10. Focused tests, full ERT, and required Ubuntu/Windows gates pass with no unexpected failures.
11. Generated `config.el` and `.elc` artifacts remain ignored and untracked.
12. No unrelated subsystem cleanup is included.

## Follow-up

After this refactor is merged, address the `company-dabbrev` failure as a separate bounded fix. The clean ownership boundary should make that investigation smaller: ESS-specific completion configuration will have one clear owner (`p3-config-ess.el`) while generic Company configuration remains in `p3-config-completion.el`.
