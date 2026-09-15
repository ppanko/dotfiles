# Emacs startup performance — Phase 2 design

## Context

Issue #80 is the umbrella performance effort. Phase 1 landed in PR #81 and removed known blocking work from ordinary file visits, reused already-resolved project identity, cached Windows tool discovery, and added a file-visit profiler. Phase 2 addresses startup latency.

The current startup path still has two structural costs that Phase 2 should address:

1. `config.org` eagerly loads most configuration ownership modules at startup, and several of those owners immediately load subsystem implementation modules such as R, Python, terminal, reference, and Org-roam helpers.
2. `p3/config-load-module` uses `load-file` on tracked `.el` source, so normal startup cannot benefit from valid machine-local compiled artifacts even when they are current.

The goal is to reduce startup work without changing the user-facing workflow, removing functionality, or creating a bespoke lazy-loading framework.

## Design principles

- Measure before changing startup behavior.
- Keep the core interactive surface eager; defer subsystem internals behind existing Emacs activation boundaries.
- Prefer normal Emacs mechanisms: autoloaded commands, mode hooks, `use-package` triggers, `with-eval-after-load`, and idle timers.
- Keep Linux and native Windows workflows equivalent unless the platform genuinely requires different internals.
- Keep tracked `.el` files authoritative.
- Preserve exact-source development reload semantics even when normal startup may use compiled code.
- Do not turn CI into a wall-clock benchmark.
- If a deferred optional subsystem fails, unrelated startup must still complete.

## Work sequence

Phase 2 is split into two implementation PRs so the baseline is captured before loading behavior changes.

### Phase 2A — startup measurement

Phase 2A changes diagnostics only. It must not intentionally change module loading, package activation, or startup ordering.

Add a lightweight startup measurement facility with named boundaries for:

- total Emacs init time;
- package initialization and `use-package` bootstrap/ensure setup;
- generated config cache validation/build/load;
- each top-level `p3-config-*` ownership module loaded from `config.org`;
- other startup phases that profiling shows are material, without proliferating micro-timers.

The facility should retain measurements for the completed startup and expose one interactive reporting command. The report should make Linux/Windows comparisons reproducible and should include enough context to distinguish package bootstrap from local configuration loading.

Hosted CI will test that instrumentation records and reports named phases. CI will not enforce elapsed-time thresholds.

Before Phase 2B changes, record representative startup results on both Linux and Windows where practical. The implementing PR should document the same scenario and measurement procedure used on each platform.

## Core-eager versus deferred loading

Phase 2B will use Phase 2A data to decide which changes are justified. The default classification is:

### Core eager

Keep startup-time behavior that is required immediately after Emacs opens or that establishes process/platform semantics needed by later modules:

- package/bootstrap boundary needed to make the configuration loadable;
- `p3-project` and project-routing semantics;
- platform setup that must exist before subprocess-using packages run, including required Windows Rtools/MSYS environment discovery;
- base commands and global keybinding surface;
- appearance/frame/modeline behavior;
- generic editing fundamentals;
- workspace/window behavior;
- completion/navigation command surface and shared Eglot integration;
- the thin configuration owners necessary to register hooks, bindings, custom variables, or autoload triggers.

Core-eager does not imply that every implementation module referenced by those owners must load eagerly.

### First-use or major-mode deferred

Defer implementation internals when their behavior is only needed after a command, package, or relevant major mode is used:

- R workflow helpers and semantic-tool implementation behind ESS/R activation or R commands;
- Python interpreter/language-tool helpers behind Python mode or Python commands;
- GPTel implementation behind GPTel activation/commands;
- reference/PDF command implementation behind reference commands and Citar/Biblio/PDF activation;
- Org presentation implementation behind presentation commands/package activation;
- terminal session implementation behind project-shell commands;
- Forge/Magit internals beyond the immediately required binding/autoload surface;
- Office/export/preview internals where existing commands can act as the loading boundary;
- other local modules shown by Phase 2A measurements to impose meaningful startup cost without providing immediate startup behavior.

The design does not require every candidate above to be deferred. Phase 2B should change only measured or structurally obvious eager work whose activation boundary can be made explicit and tested.

## Org-roam behavior

Preserve automatic Org-roam availability, but remove database initialization from the critical startup path.

Requirements:

- Org-roam bindings remain available immediately after startup.
- The Org-roam implementation/package may remain unloaded until its activation boundary.
- After normal startup completes, schedule automatic Org-roam initialization from an idle/deferred callback.
- The callback should initialize database autosync once if it has not already been activated by an earlier user command.
- Using an Org-roam command before the idle callback must activate the subsystem immediately and must make the later callback a no-op.
- An Org-roam initialization/database failure must be reported without aborting unrelated Emacs startup.
- Reloading the configuration must not accumulate duplicate timers or repeat successful initialization unnecessarily.

This preserves the existing expectation that the database becomes available automatically while removing it from the startup critical path.

## Local compiled-module loading

Normal startup and explicit development reload have different requirements and should have separate loader contracts.

### Normal startup contract

Normal startup may use a valid compiled artifact for a local module.

- Tracked `lisp/<module>.el` remains the authoritative source.
- Machine-local `.elc`/native artifacts remain untracked.
- A compiled artifact may be used only when Emacs considers it current relative to source; newer source must win.
- `load-prefer-newer` remains part of the safety contract.
- Missing compiled code falls back to source without error.
- The implementation should use normal Emacs load resolution rather than a custom compiled-artifact index or cache.

The likely interface is a startup-oriented loader that loads the module by feature/name through `load-path`, allowing Emacs to choose current compiled code or source.

### Exact-source reload contract

Explicit configuration reload must continue to execute the tracked source immediately.

- `p3/config-reload` rebuilds the generated `config.el` from `config.org` and reloads it.
- During that explicit reload, local module loads must use the exact tracked `.el` path and ignore older compiled artifacts.
- Editing a tracked local module and invoking the reload command must expose the edited source in the same Emacs session without requiring recompilation or restart.

This can be implemented with separate startup/source-loading functions or with an explicit dynamic reload mode. The distinction must be visible in tests rather than inferred from timestamps.

## Package bootstrap and auto-compile

Phase 2A must measure the existing `package-initialize`, resilient `use-package` bootstrap, and eager `auto-compile` activation instead of assuming they are either free or dominant.

Phase 2B may alter these boundaries only if measurements justify it.

Constraints:

- dependency recovery for a fresh machine must remain reliable;
- normal startup with all required packages already installed should not perform unnecessary network work;
- package installation remains an exceptional/bootstrap path, not a normal recurring startup cost;
- removing or deferring `auto-compile` must not weaken the compiled/source freshness contract above;
- no separate package manager or bespoke compilation daemon is introduced as part of this work.

## Failure and reload behavior

Deferred subsystems fail locally at their activation boundary. A missing or broken optional package must not prevent unrelated Emacs startup.

For automatic deferred tasks such as Org-roam initialization, failures should use normal warnings/messages and leave the subsystem retryable by its ordinary command path.

Configuration reload must remain idempotent:

- no duplicate hooks;
- no duplicate timers;
- no duplicate advice;
- no stale compiled code shadowing edited source;
- commands and keymaps remain available after repeated reloads.

## Testing strategy

Phase 2A tests structural measurement behavior, not performance numbers:

- named startup phases are recorded;
- reporting works after startup;
- instrumentation itself does not require optional subsystems;
- Linux and Windows CI both exercise the diagnostic code where platform-specific startup boundaries differ.

Phase 2B adds structural regression coverage for the loading model:

- selected deferred subsystem implementation features are absent after the startup/config-registration path;
- each deferred subsystem loads on its intended command/mode/package trigger;
- Org-roam idle initialization occurs once and is skipped if first use already initialized it;
- Org-roam deferred failure does not abort the rest of startup;
- normal local-module loading can select a current compiled artifact;
- newer source wins over stale compiled code;
- explicit config reload executes newly edited tracked source even when compiled artifacts exist;
- repeated reloads do not duplicate hooks, timers, advice, or bindings;
- existing project, ESS/R, Python, Org, Git, terminal, GPTel, reference, and presentation regression suites remain green on Linux and native Windows.

No hosted CI test should fail solely because startup took more than an elapsed-time threshold.

## Measurement protocol

Use the same measurement command and startup scenario before and after Phase 2B.

At minimum record:

- platform and Emacs version;
- total init time;
- package/bootstrap phase;
- config-cache validation/load phase;
- named top-level configuration-module phases;
- any additional material phase identified by the report.

For each platform, use a normal installed-package state rather than a fresh dependency-install bootstrap unless explicitly measuring the bootstrap path itself. Restart Emacs between samples. A small repeated sample is useful for distinguishing a one-off cold filesystem event from a stable startup cost, but the PR should report observed values rather than claim a CI-grade benchmark.

## PR boundaries

### PR 2A — instrument startup

- add startup diagnostic/reporting support;
- add structural tests;
- document the baseline procedure;
- capture and report baseline numbers on Linux and Windows where practical;
- no intentional lazy-loading or loader-semantics changes.

### PR 2B — streamline startup

- implement the measured core-eager/deferred boundaries;
- make Org-roam autosync idle/deferred;
- allow safe compiled local-module loading during normal startup;
- preserve exact-source explicit reload behavior;
- add structural regression coverage;
- repeat the Phase 2A measurements and document before/after results.

If Phase 2A shows package/bootstrap behavior is a distinct dominant problem that cannot be safely addressed with the same changes, isolate it into a follow-up PR rather than expanding PR 2B opportunistically.

## Non-goals

- Deferring everything merely to minimize a benchmark number.
- Removing existing workflows or making commands unavailable until users manually require implementation files.
- Replacing `use-package`, `package.el`, project.el, or the existing literate-config model.
- Introducing a bespoke lazy-loading framework, module registry, or compiled-artifact cache.
- Making Linux and Windows visibly different at the workflow level.
- Using hosted CI timing thresholds as the definition of success.
- Folding unrelated configuration cleanup into the performance work.

## Completion criteria

Phase 2 is complete when:

- a repeatable startup measurement exists and a pre-change baseline has been recorded;
- measured non-core startup work has been moved behind safe activation boundaries where justified;
- Org-roam database autosync is automatic but no longer on the startup critical path;
- normal startup can benefit from valid local compiled artifacts;
- stale compiled artifacts cannot override newer source;
- explicit reload still executes exact edited source immediately;
- Linux and Windows regression suites cover the resulting behavior;
- the same startup measurement is repeated after optimization and the implementing PR reports the result;
- issue #80 can then be closed with the remaining Phase 1 measurement status and Phase 2 evidence explicitly documented.