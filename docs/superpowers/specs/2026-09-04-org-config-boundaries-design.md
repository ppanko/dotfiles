# Org Configuration Boundaries Design

## Goal

Decompose the remaining Org-related configuration in `config.org` into focused declarative configuration modules and reusable behavior libraries while preserving current behavior and startup ordering.

This is a structural refactor only. It does not redesign Org, Org-roam, Org Agenda, Org Babel, presentations, citations, export formats, or note-taking workflow.

## Current State

The remaining Org area in `config.org` combines several distinct responsibilities:

- Org core settings, mode hooks, Babel language enablement, TODO states, agenda sorting, PDF opening, and activation of the existing Pandoc exporter;
- reusable Org commands such as TODO sorting and region-to-checkbox conversion;
- Org-roam package configuration, capture templates, bindings, display settings, and autosync;
- Org-roam helper behavior for tagged note insertion, ripgrep search, tag filtering, note enumeration, and agenda construction;
- Org presentation package wiring plus substantial stateful presentation behavior.

`lisp/p3-org-export.el` is already a focused reusable behavior library and has its own tests. It should remain intact and retain its current loading/reload semantics.

Citation/BibTeX/RefTeX configuration and LaTeX configuration are adjacent to Org functionality but have distinct dependencies and ownership. They are deliberately excluded from this PR.

## Chosen Architecture

The refactor introduces three declarative configuration owners and three behavior libraries:

```text
config.org
  |
  +--> p3-config-org
  |      +--> p3-org
  |      +--> p3-org-export   ; existing library, activated as today
  |
  +--> p3-config-org-roam
  |      +--> p3-org-roam
  |
  +--> [Poly-R remains here]
  |
  +--> p3-config-org-present
         +--> p3-org-present
```

The three module-loader stanzas remain in the same broad positions currently occupied by the Org, Org-roam, and Presentation sections. The PR must not collapse them into one adjacent block or otherwise normalize their ordering.

In particular, Poly-R remains between Org-roam and Presentation exactly as it is now.

## `p3-config-org.el`

`lisp/p3-config-org.el` becomes the declarative owner for Org core configuration. It owns the current behavior and values for:

- `org-startup-folded` = `content`;
- timestamp-on-save setup for `#+last_modified:`;
- the existing `use-package org` declaration;
- `C-c s` insertion of an Emacs Lisp source block;
- Org-mode hooks for `flyspell-mode`, `visual-line-mode`, and `org-indent-mode`;
- Org Babel language enablement for Emacs Lisp, R, C, Python, LaTeX, and shell;
- `org-confirm-babel-evaluate t`;
- native source fontification/tab behavior;
- hidden emphasis markers;
- the existing Org ellipsis;
- the `C-c C-x C-o` binding for `p3/org-sort-todos`;
- Linux PDF opening through Evince;
- TODO sequence `TODO -> WAIT -> DONE` and the existing WAIT face;
- the existing `org-agenda` package declaration and priority-down sorting strategy;
- activation of the existing Pandoc-backed export workflow from `p3-org-export.el`.

The commented-out `org-bullets` block has no runtime effect and does not need to be preserved as executable configuration. If retained for historical context, it should remain comment-only and should not create another owner.

### Core behavior loading

`p3-config-org.el` exact-source loads `p3-org.el` through `p3/config-load-module` before binding commands from it.

`p3-org.el` must not require Org merely to define its commands. It should use declarations where needed so exact-source loading the behavior library does not force Org earlier than the current configuration does.

The existing anonymous timestamp-on-save hook is preserved as an anonymous hook form in this PR. Do not opportunistically name, deduplicate, or otherwise change its reload behavior while moving it.

### Existing exporter timing and reload behavior

`p3-org-export.el` already requires Org and is currently activated through:

```elisp
(use-package p3-org-export
  :ensure nil
  :demand t
  :config
  (p3-org-export-setup))
```

That activation form moves into `p3-config-org.el` unchanged in substance. The configuration module must **not** exact-source load `p3-org-export.el` through `p3/config-load-module`.

The current order is preserved semantically:

1. establish the Org core settings/hooks and evaluate the existing `use-package org` declaration, including Babel setup;
2. define/bind the extracted core Org commands;
3. evaluate the existing `use-package p3-org-export` activation at the point where it exists today;
4. continue with PDF opening, TODO configuration, and agenda configuration in their current relative order where that order can be observed.

This preserves both startup timing and current reload behavior. `C-c r` will re-evaluate the moved `use-package p3-org-export` declaration just as it re-evaluates that declaration today, but it will not gain new exact-source reload semantics for the exporter implementation.

`p3-org-export.el` itself is unchanged in this PR.

## `p3-org.el`

`lisp/p3-org.el` owns reusable Org commands currently defined inline:

- `p3/org-sort-todos`;
- `org-set-line-checkbox`.

The existing names and semantics are preserved. In particular, this PR does not rename the legacy unprefixed `org-set-line-checkbox` command.

The behavior library contains no `use-package` declarations and no configuration-module dependencies.

## `p3-config-org-roam.el`

`lisp/p3-config-org-roam.el` becomes the declarative owner for Org-roam. It exact-source loads `p3-org-roam.el` before wiring commands from it, then preserves the current `use-package org-roam` declaration exactly in substance:

- `after-init . org-roam-mode` hook;
- SQLite built-in database connector;
- `~/org/notes/roam/` directory;
- completion everywhere and default completion system;
- the existing default and literature-note capture templates;
- the current literature-note target expression using `citar-org-roam-subdir`, `citar-citekey`, `citar-date`, and `note-title`;
- `journal/` dailies directory;
- the existing dailies capture template;
- all current `C-c n ...` bindings;
- the existing node display template;
- `org-roam-db-autosync-mode` activation.

The earlier `citar-org-roam` declaration remains outside this PR. Its existing `:after (citar org-roam)` relationship must continue to work when Org-roam is loaded from the new configuration module.

No capture template, path, keybinding, or database behavior is redesigned here.

## `p3-org-roam.el`

`lisp/p3-org-roam.el` owns the reusable helper behavior currently inline:

- `org-roam-generate-tagged-header`;
- `org-roam-node-insert-immediate-with-tag`;
- `org-roam-rg-search`;
- `p3/org-roam-filter-by-tag`;
- `p3/org-roam-list-notes`;
- `p3/org-roam-list-notes-by-tag`;
- `p3/org-roam-get-agenda`.

Existing function names are preserved, including the legacy unprefixed Org-roam helper names.

The library may require generic built-ins such as `seq` and `subr-x`, but it must not require `org-roam` solely to define these functions. Org-roam functions and variables should be declared as needed for warnings-as-errors byte compilation. This preserves the current package-loading boundary.

The agenda helper retains its existing semantics: prompt for a tag, set `org-agenda-files` to all Roam notes or only tagged notes, then invoke `org-agenda`.

The current nonblank branch of `org-roam-generate-tagged-header` produces a header string whose final line ends with a stray `#`. That output is odd but observable behavior. This structural PR preserves it exactly and tests for it explicitly rather than silently correcting it.

## `p3-config-org-present.el`

`lisp/p3-config-org-present.el` becomes the declarative presentation owner. It preserves:

- `use-package hide-mode-line` with the current `:after (org-present)` relationship;
- `use-package visual-fill-column`;
- the existing `use-package org-present` declaration;
- `C-c P` from `org-mode-map`;
- all current presentation-mode navigation/fullscreen/quit bindings;
- the current enter/quit hooks;
- `org-present-text-scale 4`.

The module preserves the current executable sequence exactly in substance:

1. declare `hide-mode-line` with `:after (org-present)`;
2. declare/load `visual-fill-column` as it is loaded today;
3. exact-source load `p3-org-present.el`, which itself requires built-in `face-remap` before defining the presentation behavior;
4. evaluate the `use-package org-present` declaration that binds those commands and installs the existing hooks.

This keeps `face-remap` at the same effective point in the sequence while giving the behavior library direct ownership of the built-in dependency it actually calls.

No new display-buffer or window-placement policy is introduced.

## `p3-org-present.el`

`lisp/p3-org-present.el` owns the stateful presentation behavior currently inline:

- buffer-local `p3/org-present--state`;
- `p3/org-present-start`;
- `p3/org-present-toggle-fullscreen`;
- `p3/org-present-hook`;
- `p3/org-present-quit-hook`;
- `p3/org-present-prev`;
- `p3/org-present-next`.

The library directly requires built-in `face-remap`, because its enter/quit behavior calls `face-remap-add-relative` and `face-remap-remove-relative`. It must not rely on its configuration owner having loaded that dependency incidentally.

The exact presentation behavior is frozen:

- presentation start rejects non-Org buffers;
- current header-line state is saved and restored;
- current line-number state is saved and restored;
- existing inline-image state is preserved;
- `org-present-big` / `org-present-small` behavior is retained;
- visual-fill width remains 90 and centered during presentation;
- prior visual-fill state and settings are restored on quit;
- prior hide-mode-line state is restored on quit;
- Org level 1/2/3 face remapping remains 1.5/1.2/1.1;
- face-remap cookies are removed on quit;
- presentation state is cleared after restoration;
- navigation wrappers continue to delegate to `org-present-next` and `org-present-prev`;
- fullscreen continues to toggle the frame's `fullscreen` parameter to/from `fullboth`.

The behavior library contains no `use-package` declarations and no dependency on `p3-config-org-present.el`.

## `config.org` End State

The existing Org section is reduced to concise prose and:

```elisp
(p3/config-load-module 'p3-config-org)
```

The existing Org-roam section is reduced to concise prose and:

```elisp
(p3/config-load-module 'p3-config-org-roam)
```

The existing Presentation section is reduced to concise prose and:

```elisp
(p3/config-load-module 'p3-config-org-present)
```

These stanzas stay in their current relative locations. `config.org` must still visibly communicate the broad subsystem sequence rather than hiding it inside one umbrella Org module.

## Behavior and Ordering Freeze

This PR preserves all current user-facing behavior and broad startup order.

Specifically:

- Org core remains before Org Agenda and Org-roam;
- Org Agenda remains configured before the Roam-backed agenda helper is used;
- Org-roam remains in its current position;
- Poly-R remains between Org-roam and Presentation;
- Presentation remains in its current position before Projectile/Python;
- the earlier Citar/BibTeX/RefTeX configuration stays where it is;
- `citar-org-roam` remains outside the new Roam module and retains its `:after` relationship;
- LaTeX configuration stays where it is;
- the existing Pandoc exporter implementation and its current loading/reload semantics stay unchanged;
- no keybindings are renamed or moved to new keys;
- no Org Babel language is added or removed;
- Babel confirmation remains enabled;
- no agenda workflow is redesigned;
- no Roam path/template/database behavior is redesigned;
- the stray trailing `#` in nonblank tagged Roam headers is preserved;
- no presentation UX is redesigned;
- no broad window-management rule is introduced;
- no anonymous hooks, legacy function names, or other odd-but-working forms are opportunistically normalized merely because they move files.

## Exact-Source Reload Semantics

The three new configuration modules are loaded through `p3/config-load-module`, so `C-c r` re-evaluates their current tracked source.

Each new configuration owner exact-source loads its newly extracted behavior library so edits to `p3-org.el`, `p3-org-roam.el`, and `p3-org-present.el` are picked up by configuration reload, matching the pattern already used for migrated ESS/Python behavior boundaries.

The existing exporter is the deliberate exception. `p3-config-org.el` retains the current `use-package p3-org-export :demand t` activation instead of exact-source loading `p3-org-export.el`, so this PR does not change exporter implementation reload semantics.

No module registry, scanning, autoload framework, or recursive generic reload mechanism is added.

## Testing Strategy

### Core Org behavior tests

Add focused tests for `p3-org.el` covering at minimum:

- `p3/org-sort-todos` delegates to `org-sort-entries` with the current arguments;
- `org-set-line-checkbox` preserves single-line behavior;
- region behavior prefixes every selected line with `- [ ] ` and retains the current cursor semantics.

### Org configuration-boundary tests

Add source-semantic tests for `p3-config-org.el` that verify:

- exact-source loading of `p3-org.el` occurs before command binding;
- the existing Org mode hooks are preserved;
- the exact Babel language set is preserved;
- Babel confirmation remains `t`;
- Org visual/source settings and ellipsis are unchanged;
- `C-c s` and `C-c C-x C-o` remain bound to the same behavior;
- the anonymous timestamp hook remains behaviorally unchanged;
- the existing `use-package p3-org-export` activation remains after the Org declaration and is not replaced with exact-source loading;
- Linux PDF handling remains unchanged;
- TODO keywords/faces remain unchanged;
- Org Agenda sorting remains `priority-down`.

### Org-roam behavior tests

Add focused tests for `p3-org-roam.el` using stubs rather than a real Org-roam database. Cover at minimum:

- tagged-header output for a blank tag;
- the exact nonblank tagged-header string, including its current trailing `#`;
- tag predicate behavior;
- note enumeration from stubbed nodes;
- tagged note filtering;
- agenda file selection for blank and nonblank tag input;
- ripgrep search delegates to `consult-ripgrep` with `org-roam-directory`;
- immediate insertion temporarily uses the tagged capture template and delegates to `org-roam-node-insert`.

### Org-roam configuration-boundary tests

Source-semantic tests should pin:

- exact-source load of `p3-org-roam.el` before its commands are wired;
- all current `org-roam` custom values;
- both capture templates and the dailies template;
- all current `C-c n` bindings;
- node display template;
- autosync activation;
- absence of the moved helper definitions from `config.org`.

Tests should not create a real Roam database or depend on the user's notes directory.

### Presentation behavior tests

Add focused tests for `p3-org-present.el` with external presentation/display functions stubbed. Cover at minimum:

- direct ownership of the built-in `face-remap` dependency;
- non-Org start rejection;
- fullscreen toggle behavior;
- enter hook captures relevant prior buffer state and applies presentation state;
- quit hook restores saved state and clears `p3/org-present--state`;
- navigation wrappers delegate to `org-present-next` / `org-present-prev`.

The state-restoration test is important because moving these functions is the highest-risk part of the refactor.

### Presentation configuration-boundary tests

Source-semantic tests should pin:

- package relationships for `hide-mode-line`, `visual-fill-column`, and `org-present`;
- the exact effective sequence `hide-mode-line -> visual-fill-column -> p3-org-present[face-remap] -> org-present`;
- all current presentation bindings;
- both presentation hooks;
- `org-present-text-scale 4`.

### Architecture tests

Update `test/p3-config-test.el` to verify:

- configuration-module count increases from seven to ten;
- the three new module-loader stanzas each occur exactly once;
- their broad order is Org -> Org-roam -> Poly-R -> Presentation;
- moved Org/Roam/Presentation function definitions are absent from `config.org`;
- the existing citation/BibTeX/RefTeX and LaTeX blocks remain in `config.org`;
- Org Babel's Python/R/etc. references are not mistaken for configuration-ownership leaks;
- `p3-org-export.el` remains a behavior library rather than being folded into a new module.

### Runtime-load smoke tests

The CI design must verify evaluation, not only parsing and byte compilation.

Ubuntu should smoke-load each new configuration owner in batch Emacs with package installation suppressed:

- `p3-config-org.el` must evaluate successfully and provide `p3-config-org` and `p3-org` while preserving the expected core Org configuration state;
- `p3-config-org-roam.el` must evaluate successfully with the optional Org-roam package surface stubbed/provided by the test harness rather than installed, and must provide both `p3-config-org-roam` and `p3-org-roam`;
- `p3-config-org-present.el` must evaluate successfully with `hide-mode-line`, `visual-fill-column`, and `org-present` package surfaces stubbed/provided by the harness rather than installed, and must provide both `p3-config-org-present` and `p3-org-present`.

The smoke harness must avoid opening a real Roam database, touching the user's notes directory, starting presentation mode, or installing optional third-party packages. Its purpose is to catch load-order, missing-variable, missing-function, and package-wiring failures in the actual modules.

### CI

Ubuntu should:

- byte-compile all six new Lisp files with warnings treated as errors and package installation suppressed;
- run all three runtime-load smoke checks;
- run the new focused behavior/configuration-boundary tests;
- run the existing `p3-org-export` tests unchanged;
- run the full ERT suite as the final regression gate.

Windows should cover source-level architecture/configuration-boundary tests when the changed files participate in portable configuration structure. It should not install Org-roam or presentation packages or create a second broad runtime suite solely for this refactor.

Optional third-party packages must not be installed merely to byte-compile or smoke-load the new modules. Compiler-only `defvar` and `declare-function` forms and smoke-test-only package stubs are acceptable when needed and must not change runtime behavior.

## Out of Scope

This PR does not:

- redesign Org workflows;
- change Org Babel languages or execution-confirmation policy;
- rename existing Org commands;
- change Org Agenda semantics;
- redesign Org-roam capture templates, database settings, note paths, or keybindings;
- fix the current trailing `#` emitted by nonblank tagged Roam headers;
- redesign the presentation experience;
- change the Pandoc export implementation, supported formats, or reload semantics;
- reorganize Citar, `citar-org-roam`, BibTeX, RefTeX, or citation configuration;
- reorganize LaTeX configuration;
- change Poly-R;
- change Projectile;
- change completion technology;
- add display/window-placement rules;
- introduce module discovery or a registry.

## Acceptance Criteria

The refactor is complete when:

1. `p3-config-org.el` is the sole declarative owner for Org core/Agenda/export activation configuration in this scope;
2. `p3-org.el` owns the extracted reusable Org commands with unchanged behavior;
3. `p3-config-org-roam.el` is the sole declarative Org-roam owner;
4. `p3-org-roam.el` owns the extracted Roam helper behavior with unchanged semantics, including the current trailing `#` in nonblank tagged headers;
5. `p3-config-org-present.el` is the sole declarative Org presentation owner;
6. `p3-org-present.el` owns the stateful presentation behavior, directly owns its `face-remap` dependency, and preserves restoration semantics;
7. `p3-org-export.el` remains unchanged and retains its current `use-package`-based activation/reload behavior;
8. `config.org` contains the three concise loader stanzas in the same broad positions as the old sections;
9. Poly-R remains between Roam and Presentation;
10. citation/BibTeX/RefTeX and LaTeX configuration remain outside this refactor;
11. existing keybindings/settings/templates are semantically unchanged;
12. no odd-but-working hooks or legacy command names are normalized as part of the move;
13. new modules/libraries byte-compile cleanly without optional-package installation churn;
14. each new configuration owner passes a runtime-load smoke check without optional-package installation or external side effects;
15. focused and full regression suites pass on the intended CI platforms;
16. no unrelated subsystem or behavior change is included.
