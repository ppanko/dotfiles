# Retire Projectile in Favor of project.el

## Goal

Remove Projectile from the active Emacs architecture now that built-in `project.el` is already the sole source of P3 project identity. Preserve the project boundaries and user workflows that still matter without retaining a second project framework.

This change is a cleanup of the project interaction layer, not a redesign of project semantics. ESS, Python, R tooling, and terminal behavior must continue to consume `p3/project-root` exactly as they do today.

## Current state

`p3-project.el` is loaded from `init.el` before the literate configuration and establishes native project semantics. It currently:

- requires built-in `project`;
- adds `.projectile` to `project-vc-extra-root-markers`;
- removes Projectile's `project-projectile` provider whenever `projectile-mode` runs;
- exposes `p3/project-root` and `p3/use-project-root-as-default-dir`.

`config.org` still enables Projectile only as a command/UI layer. It binds `s-p` and `C-c p` to `projectile-command-map`, enables `projectile-mode`, and registers an R project type.

The earlier project.el foundation deliberately retained Projectile temporarily. This change completes that migration.

## Design

### Native project identity remains authoritative

`p3-project.el` remains the startup-critical project identity owner and stays required from `init.el` before normal configuration loading.

The helper contract remains unchanged:

- `p3/project-root` delegates to `project-current` and `project-root`;
- callers that fall back to `default-directory` keep doing so;
- no custom project backend is introduced.

### Remove the Projectile runtime

Delete all active Projectile configuration:

- the `use-package projectile` declaration;
- `projectile-mode` activation;
- `projectile-command-map` bindings;
- `p3/projectile-r-project-file-p`;
- Projectile R project-type registration.

Remove the Projectile-specific defensive policy from `p3-project.el`:

- the `project-projectile` declaration;
- `p3/project-keep-native-provider`;
- the `projectile-mode-hook` registration;
- the one-time provider cleanup call.

After this change, no active source configuration should load, enable, configure, or call Projectile.

The change does not attempt to uninstall an already-installed Projectile package from a user's package directory. Package retirement means it is no longer part of the configuration or startup path.

An already-running Emacs session is a special transition case. Because `projectile-mode` is currently enabled as a global minor mode, removing its configuration does not by itself disable that already-active mode or remove its minor-mode keymap/provider state during `C-c r`. The retirement is therefore considered complete only after one Emacs restart following adoption of this change. Do not add permanent runtime cleanup code merely to make the transition hot-reloadable.

### Native project command interface

Add `lisp/p3-config-project.el` as the declarative owner of the user-facing native project bindings.

It will require built-in `project` and bind:

- `C-c p` to `project-prefix-map`;
- `s-p` to `project-prefix-map`.

The standard built-in `C-x p` binding remains untouched.

This preserves the two existing high-level entry keys while replacing the implementation behind them with built-in `project.el` commands. It does not preserve Projectile's command semantics. Native `project-switch-project`, `project-find-file`, remembered-project behavior, and the rest of `project-prefix-map` should retain their built-in behavior rather than be configured to imitate Projectile.

In particular, users may initially see a different switch-project flow and fewer remembered projects. That is an intentional migration cost, not a regression to be papered over with compatibility wrappers.

The new aliases live in the global map rather than Projectile's global minor-mode map, so their keymap precedence is slightly lower than before. `C-c p` is a user-reserved prefix and `s-p` is an explicit personal binding; accept this simplification unless an actual conflict is demonstrated. Do not introduce another global minor mode merely to reproduce Projectile's keymap precedence.

No compatibility wrapper command or copied Projectile keymap is introduced.

`config.org` will load `p3-config-project` in the same relative location currently occupied by the Projectile block: after Presentation and before Python. That avoids unrelated startup-order changes.

### Forward project marker for R projects

Newly generated R projects should stop creating an empty `.projectile` file.

Instead, add `"*.Rproj"` to `project-vc-extra-root-markers` in `p3-project.el`. Emacs 29's `project.el` supports glob patterns in `project-vc-extra-root-markers`, so the existing `<project-name>.Rproj` file can define the project boundary without a Projectile-specific sentinel.

This preserves the important current semantic: an R analysis directory can define an inner project boundary even when it lives inside a larger Git repository.

The R scaffolder will therefore remove `(:path ".projectile" :content "")` from `p3-r--common-project-files` and continue creating the existing `.Rproj` file unchanged.

### Legacy `.projectile` compatibility

Keep `.projectile` in `project-vc-extra-root-markers` for now.

This is intentionally a compatibility marker only. Existing projects may depend on it to define non-VCS or nested project boundaries. Removing support in the same change that retires the Projectile package could silently change project roots.

No migration script, bulk repository rewrite, warning system, or automatic marker replacement is added. Existing `.projectile` files continue to work; new generated R projects stop creating them.

A later cleanup can remove `.projectile` support only after there is evidence that no remaining projects require it.

### Project list behavior

Do not migrate Projectile's remembered-project database into `project.el`.

Native `project.el` maintains its own known-project list. Users may initially see fewer remembered projects in `project-switch-project`; selecting recognized projects through native project commands will repopulate that list normally. Arbitrary unmarked directories should not be treated as persistently known projects merely to mimic Projectile.

Writing a one-off Projectile cache importer would add compatibility machinery for a framework being removed and is outside this design.

### Keybinding atlas

Add a compact `Project` section to `p3/keybinding-sections` documenting the native project entry points, centered on `C-c p` / `C-x p`.

Do not enumerate every command under the native project prefix. The atlas should remain a concise workflow guide rather than duplicate Emacs help.

## Compatibility and non-goals

This change must not:

- alter `p3/project-root` semantics beyond adding `*.Rproj` as a recognized native marker;
- change ESS process/session behavior;
- change Python environment selection except insofar as the same project root continues to be consumed;
- change terminal root or placement behavior;
- add project tabs or a new project UI package;
- add a custom `project.el` backend;
- reproduce Projectile command semantics on top of `project.el`;
- migrate Projectile's remembered-project database;
- uninstall packages from user package directories;
- rename or delete existing `.projectile` files;
- add persistent Projectile shutdown/cleanup machinery for already-running sessions;
- modify historical specs/plans to pretend Projectile was never part of the migration path.

The supported Emacs baseline remains 29+.

## Windows contract

The existing Windows project contract remains mandatory.

Marker-defined non-VCS projects must still be detectable and enumerable after the existing Rtools/MSYS2 platform setup provides a Unix-compatible `find` program. This is particularly important because native `project.el` file enumeration for marker-only projects relies on that external `find` path on Windows.

Windows coverage should exercise the forward marker (`*.Rproj`) rather than only the legacy `.projectile` marker, while ordinary cross-platform tests continue to prove legacy `.projectile` compatibility.

The Windows workflow must also remain durable for future isolated edits to the new project config owner. Add both `lisp/p3-config-project.el` and its focused test file to `.github/workflows/windows-platform-tests.yml` path filters, compile the owner in the Windows byte-compilation gate, and load its focused test where the existing Windows architecture tests run.

No new Windows-specific project implementation should be introduced.

## Tests

Implementation must establish these invariants:

1. Active configuration contains no Projectile package declaration, activation, command-map binding, project-type registration, or `project-projectile` provider policy.
2. `p3-project.el` remains loaded from `init.el` before the literate config and continues to own project semantics.
3. `C-c p` and `s-p` resolve to native `project-prefix-map`; standard `C-x p` remains native.
4. A normal Git repository is recognized by `project.el`.
5. An `*.Rproj`-only project is recognized from a descendant directory.
6. A nested `*.Rproj` marker inside an outer Git repository resolves to the inner project root, and `project-files` for that project includes files inside the inner project while excluding sibling files that belong only to the outer repository.
7. A legacy `.projectile` marker still defines a project root.
8. Newly generated R projects contain the normal `.Rproj` file and no longer create `.projectile`.
9. Existing ESS, Python, R-tool, and terminal tests continue to prove shared `p3/project-root` consumption without behavioral drift.
10. Native Windows tests detect and enumerate an `*.Rproj`-defined project after normal platform setup.
11. `p3-config-project.el` byte-compiles with warnings treated as errors and has a focused smoke/boundary test.
12. The Windows workflow path filters, compile step, and architecture-test load list include the new project config owner and focused test.
13. The aggregate config architecture tests reflect the new project config owner and the removal of inline Projectile configuration.
14. The full ERT suite remains green.

The transition note must also be verified manually/documentarily: after adopting the merged change, restart Emacs once rather than relying on `C-c r` to disable an already-running Projectile session.

Use static/local review and focused tests first. Run the normal Ubuntu and Windows CI workflows as one coherent final gate rather than as an iterative diagnostic loop.

## Expected result

After this change and one Emacs restart:

- `project.el` is the only project framework in active use;
- `p3-project.el` owns early project semantics and marker policy;
- `p3-config-project.el` owns native project keybindings;
- Git and `*.Rproj` are the forward project-boundary mechanisms;
- `.projectile` remains only as legacy compatibility;
- newly generated R projects no longer contain Projectile-specific files;
- no Projectile compatibility layer remains in runtime code.
