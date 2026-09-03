# Project.el Foundation Design

## Goal

Make built-in `project.el` the single source of project identity for the Emacs configuration. R/ESS, Python, R helpers, and project-aware terminals should all consume the same project root. Projectile remains installed and usable during this PR, but it no longer determines P3 project semantics.

This design targets Emacs 29 or newer. That baseline is required because this PR relies on `project-vc-extra-root-markers` for native recognition of existing `.projectile` project markers.

## Scope

This PR is limited to project identity and project-root plumbing. It does not redesign ESS process management, Python environment management, buffer placement, completion, startup/tangling, Org-roam, or Projectile keybindings.

The normal one- or two-window workflow must remain unchanged.

One intentional semantic change is included: Python will use the same shared project root as the other P3 subsystems. In nested cases where a `.projectile` marker defines an inner project inside a larger VCS repository, Python will now use the inner project root as well. This aligns Python with the existing P3/Projectile project semantics and is covered explicitly by tests.

## Architecture

Introduce `lisp/p3-project.el` as the owner of project discovery and project-root helpers.

`p3-project.el` will:

- require built-in `project`;
- register `.projectile` in `project-vc-extra-root-markers`;
- prevent Projectile's `project-projectile` backend from remaining in `project-find-functions` when `projectile-mode` is enabled;
- expose the existing `p3/project-root` interface, backed only by `project-current` and `project-root`;
- expose `p3/use-project-root-as-default-dir`.

Keeping `.projectile` as the marker in this PR is intentional. Existing non-VCS R projects and newly generated R projects remain recognizable to Projectile, while `project.el` gains the same root marker. A later PR can decide whether Projectile is still useful and whether the marker should be renamed.

Projectile itself integrates with `project.el` by adding `project-projectile` to `project-find-functions` whenever `projectile-mode` is enabled. That would make Projectile the effective provider behind `project-current`, even though P3 no longer calls `projectile-project-root` directly. P3 therefore attaches a small policy function to `projectile-mode-hook` that removes `project-projectile` after Projectile updates its hooks. Projectile remains enabled for its commands, project list, and UI; it simply does not supply P3's `project.el` identity. The same policy is applied once when `p3-project.el` loads so reloading the module repairs an already-active Projectile session.

Registration of `.projectile` is startup-critical. `p3-project.el` must be loaded before any P3 subsystem or package configuration is allowed to call `project-current`, because `project.el` may cache project detection. The bootstrap therefore requires `p3-project` in `init.el` immediately after the P3 Lisp directory enters `load-path` and before the literate configuration is tangled or loaded. This is an intentionally narrow bootstrap responsibility, not a broader startup/tangling redesign.

The existing platform setup still configures Rtools/MSYS2 early in the literate configuration before normal project-aware workflows run. Registering the project marker itself does not depend on those Unix tools; project file enumeration on Windows does, and is covered separately by the Windows integration gate.

`p3-core.el` will return to genuinely shared configuration helpers and will no longer contain project discovery.

Project-aware subsystems will depend directly on `p3-project.el` rather than receiving project semantics indirectly through `p3-core.el`:

- `p3-ess.el`
- `p3-r-tools.el`
- `p3-python.el`
- `p3-terminal.el`

`p3-python.el` will stop using the separate `p3/project-el-root` helper and use the shared `p3/project-root` contract like the other subsystems.

## Project-root semantics

Normal Git/VC repositories continue to use the standard `project.el` VC-aware backend.

A `.projectile` marker additionally defines a P3 project root through `project-vc-extra-root-markers`. This applies both to non-VCS projects and to subprojects nested inside a larger VCS repository.

When both an outer VCS root and an inner `.projectile` marker are present, the inner marker is intentionally the project boundary for P3. This preserves the practical semantics of the current Projectile-first `p3/project-root` helper while moving the implementation to built-in `project.el`.

As a consequence, Python project-local interpreter discovery will also use that inner root after this PR. For example, if `~/repo/analysis/.projectile` and `~/repo/analysis/.venv` exist inside an outer Git repository at `~/repo`, Python will select `~/repo/analysis` as its project root and discover the inner `.venv`.

## Compatibility

Projectile is not removed, disabled, or re-keyed. Existing `.projectile` project markers stay in place, including the marker emitted by the R project scaffolder. Projectile commands remain available, but its `project-projectile` bridge is deliberately removed from `project-find-functions` while P3 is active so built-in project discovery remains authoritative.

The supported baseline for this design is Emacs 29+. No compatibility backend for older Emacs versions will be added in this PR. If pre-29 support becomes a real requirement, it should be handled as a separate compatibility decision rather than by retaining two competing project systems.

Git repositories continue to be recognized by the normal `project.el` VC-aware backend. Non-VCS directories containing `.projectile` are recognized through `project-vc-extra-root-markers`.

No P3 command in this PR should create additional windows or alter buffer-placement behavior.

## Windows contract

Native Windows support must preserve project discovery and file enumeration for `.projectile`-only projects.

The existing platform layer configures the Rtools/MSYS2 tool environment early in startup. The project foundation must coexist with that setup so that `project.el` can enumerate project files with a Unix-compatible `find` rather than the unrelated Windows `find.exe`.

The Windows test gate must therefore exercise both:

1. project-root detection for a temporary `.projectile`-only project; and
2. `project-files` enumeration within that project after normal P3 platform setup.

This is a behavior contract, not a request for new Windows-specific project machinery.

## Error and fallback behavior

`p3/project-root` returns nil when `project-current` finds no project, matching the current helper contract. Callers that currently fall back to `default-directory`, such as terminal and ESS helpers, retain that behavior. Callers that require a project continue to signal their existing user-facing errors.

This PR does not add a custom project backend or a Projectile fallback path.

## Tests

Add or revise ERT coverage to establish these invariants:

1. `p3/project-root` delegates to `project-current`/`project-root`.
2. When Projectile inserts `project-projectile` ahead of native providers, the P3 `projectile-mode-hook` policy removes it and a real `project-current` lookup proceeds through the native provider.
3. A temporary `.projectile`-only directory is recognized through the public `project-current` contract, including from a descendant directory.
4. A nested `.projectile` marker inside an outer Git repository resolves to the inner project root.
5. `p3-core.el` no longer owns project discovery.
6. Python uses the shared `p3/project-root` contract and, in the nested-project case, resolves a project-local `.venv` from the inner root.
7. ESS, R tools, and terminal helpers continue to consume `p3/project-root` without other behavioral changes.
8. `init.el` loads `p3-project` after adding the P3 Lisp directory to `load-path` and before loading the literate configuration.
9. On Windows, a `.projectile`-only project can both be detected and have its files enumerated after normal P3 platform setup.
10. The extracted modules byte-compile with warnings treated as errors.
11. The existing full ERT suite remains green.

CI should add `p3-project.el` to byte-compilation and load its tests in the normal suite. The existing Windows platform workflow should be extended narrowly enough to cover the project detection/file-enumeration contract when project/platform files change. No additional diagnostic workflow is needed.

## Non-goals

This PR will not:

- remove Projectile;
- rename `.projectile` to `.project`;
- alter project switching UI;
- introduce project tabs;
- change ESS process/session behavior;
- redesign Python environment management beyond making shared project identity authoritative;
- change vterm display behavior;
- add `display-buffer-alist` rules;
- reorganize `config.org` or startup tangling.

Those remain separate follow-up decisions after the project foundation is stable.
