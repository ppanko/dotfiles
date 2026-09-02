# Project.el Foundation Design

## Goal

Make built-in `project.el` the single source of project identity for the Emacs configuration without changing the user-facing workflow. R/ESS, Python, R helpers, and project-aware terminals should all consume the same project root. Projectile remains installed and usable during this PR, but it no longer determines P3 project semantics.

## Scope

This PR is limited to project identity and project-root plumbing. It does not redesign ESS process management, Python environments, buffer placement, completion, startup/tangling, Org-roam, or Projectile keybindings.

The normal one- or two-window workflow must remain unchanged.

## Architecture

Introduce `lisp/p3-project.el` as the owner of project discovery and project-root helpers.

`p3-project.el` will:

- require built-in `project`;
- expose the existing `p3/project-root` interface, backed only by `project-current` and `project-root`;
- expose `p3/use-project-root-as-default-dir`;
- register `.projectile` as an additional `project.el` root marker through `project-vc-extra-root-markers` when that variable is available.

Keeping `.projectile` as the marker in this PR is intentional. Existing non-VCS R projects and newly generated R projects remain recognizable to Projectile, while `project.el` gains the same root marker. A later PR can decide whether Projectile is still useful and whether the marker should be renamed.

`p3-core.el` will return to genuinely shared configuration helpers and will no longer contain project discovery.

Project-aware subsystems will depend directly on `p3-project.el` rather than receiving project semantics indirectly through `p3-core.el`:

- `p3-ess.el`
- `p3-r-tools.el`
- `p3-python.el`
- `p3-terminal.el`

`p3-python.el` will stop using the separate `p3/project-el-root` helper and use the shared `p3/project-root` contract like the other subsystems.

## Compatibility

Projectile is not removed, disabled, or re-keyed. Existing `.projectile` project markers stay in place, including the marker emitted by the R project scaffolder.

Git repositories continue to be recognized by the normal `project.el` VC-aware backend. Non-VCS directories containing `.projectile` are recognized by adding that marker to `project-vc-extra-root-markers` on Emacs versions that provide the option.

No P3 command in this PR should create additional windows or alter buffer-placement behavior.

## Error and fallback behavior

`p3/project-root` returns nil when `project-current` finds no project, matching the current helper contract. Callers that currently fall back to `default-directory`, such as terminal and ESS helpers, retain that behavior. Callers that require a project continue to signal their existing user-facing errors.

This PR does not add a custom project backend. If a supported Emacs lacks `project-vc-extra-root-markers`, Git/VC projects still work normally; `.projectile`-only non-VCS discovery remains unchanged until a compatibility need is demonstrated.

## Tests

Add or revise ERT coverage to establish these invariants:

1. `p3/project-root` delegates to `project-current`/`project-root` and does not consult Projectile.
2. `.projectile` is registered as a native project root marker where supported.
3. `p3-core.el` no longer owns project discovery.
4. Python uses the shared P3 project-root contract.
5. ESS, R tools, and terminal helpers continue to consume `p3/project-root` without behavioral changes.
6. The extracted modules byte-compile with warnings treated as errors.
7. The existing full ERT suite remains green.

CI should add `p3-project.el` to byte-compilation and load its tests in the normal suite. No additional workflow or diagnostic CI machinery is needed.

## Non-goals

This PR will not:

- remove Projectile;
- rename `.projectile` to `.project`;
- alter project switching UI;
- introduce project tabs;
- change ESS process/session behavior;
- change Python environment management;
- change vterm display behavior;
- add `display-buffer-alist` rules;
- reorganize `config.org` or startup tangling.

Those remain separate follow-up decisions after the project foundation is stable.
