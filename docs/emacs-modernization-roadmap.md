# Emacs Configuration Modernization Roadmap

## Purpose and authority

This document records the intended direction and structural status of the Emacs configuration modernization work that grew out of the configuration review and comparison against stronger example configurations.

Use the repository sources to answer what Emacs does today. Use this roadmap to answer what architectural direction is intended and what structural modernization work remains. Use GitHub Issues as the authoritative feature/UX backlog and pull requests to track active implementation. The files under `docs/superpowers/specs/` and `docs/superpowers/plans/` are detailed design and implementation history, not the current roadmap.

The roadmap intentionally does not enumerate ordinary feature issues. That backlog changes too frequently and belongs in GitHub Issues.

## Target state

The configuration should remain a personal Emacs configuration, not become a framework for managing itself.

- `init.el` owns bootstrap and prerequisites required before normal configuration loading.
- `config.org` is the concise, human-readable orchestration map.
- `lisp/p3-config-*.el` files own declarative configuration for coherent domains: package declarations, settings, hooks, bindings, and small package-specific glue.
- `lisp/p3-*.el` files own reusable behavior: commands, process/session logic, project logic, filesystem operations, transformations, and workflow implementation.
- generated `config.el` remains an ignored, content-validated startup cache of `config.org`, not a second source of truth.
- platform-specific behavior remains isolated behind focused boundaries rather than leaking through general configuration.
- Linux and Windows remain supported targets.

## Decision rules

1. **Prefer workflow value over package fashion.** Built-in Emacs facilities should replace packages when they meet the workflow at least as coherently; third-party packages should remain when they materially improve the UX or avoid unnecessary custom machinery.
2. **Keep composition explicit.** Do not add module registries, directory scanning, recursive reload frameworks, dependency-graph machinery, or multi-target tangling merely because the configuration is modular.
3. **Keep ownership narrow.** Declarative wiring belongs in `p3-config-*`; substantial reusable behavior belongs in `p3-*`. Cross-domain helpers require a real shared abstraction, not cosmetic deduplication.
4. **Preserve behavior during structural work.** Refactors should not silently redesign keybindings, project semantics, window workflows, platform behavior, or subsystem runtime contracts.
5. **Test durable contracts.** Protect startup/reload semantics, project identity, platform behavior, ownership boundaries, and workflow helpers. Avoid tests that primarily freeze formatting or incidental source shape.

## Structural status

| Area | Intended state | Status | Tracking |
| --- | --- | --- | --- |
| Bootstrap and startup | `init.el` bootstrap; resilient package setup; one validated `config.el` cache; exact-source local reloads | Complete | PRs #3, #4, #11, #12 |
| Configuration ownership | `config.org` as orchestration map; declarative `p3-config-*`; reusable `p3-*` behavior | Complete | PRs #6, #8, #12 |
| Project identity | built-in `project.el` canonical; no parallel Projectile runtime | Complete | PRs #10, #19 |
| Platform boundary | Windows/Rtools/MSYS2, shell/process coding, Hunspell, R discovery, and Windows GnuPG workarounds isolated behind `p3-platform` where appropriate | Complete for current known boundaries | PRs #2, #8, #26 |
| ESS, Python, Org, terminal, GPTel | focused declarative owners separated from reusable behavior | Structurally complete | PRs #13, #15, #16, #17, #18 |
| Editing and appearance | generic editing ownership consolidated; native mode line; Nerd Icons fallback path; no unused `workgroups2` framework | Complete for now | PRs #22, #23, #24 |
| Reference management and export | Pandoc-based document export; Citar/Org/BibLaTeX reference workflow with Org-roam literature notes | Complete for current scope | PRs #5, #21 |
| Completion | existing minibuffer and Company stack retained unless a concrete workflow deficiency justifies change | No standing redesign | — |
| Legacy/dead configuration | unused MySQL and Poly-R integrations and the commented `Not in use` graveyard removed from the live config | Complete | PR #35 |
| Package dependency lifecycle | determine whether the additional dependency-repair/preflight work is still wanted | Decision needed | draft PR #9 |

## Remaining structural modernization

### Package dependency lifecycle — draft PR #9

PR #9 should not remain indefinitely ambiguous. Its proposed scope goes beyond the already-completed bootstrap work: dependency-version repair, built-in dependency handling, fresh-process recompilation after package mutation, and preflight/fail-closed behavior.

Decide explicitly whether to finish a narrowed version because the current package lifecycle still has a demonstrated failure mode, or close it as superseded if the existing bootstrap is sufficient. Do not keep it open merely because the implementation exists.

## Feature and UX backlog

GitHub Issues is authoritative for desired user-facing configuration work. New terminal, Org-roam, project/session, language workflow, Git/document, GPTel, Office-document, command-discovery, recording, and similar features should be tracked there rather than copied into this roadmap.

Those issues should conform to the target state and decision rules above, but their existence does not by itself mean the structural modernization is incomplete.

## Not on the standing roadmap

Do not revive these directions without a new concrete problem that requires them:

- returning to a monolithic `config.org`;
- multi-target Org tangling for configuration modules;
- automatic module discovery or registries;
- a recursive/general reload framework;
- Projectile as a parallel project system;
- Doom-modeline as a required presentation layer;
- `all-the-icons` as the icon stack;
- `workgroups2` or another workspace framework merely to replace it; native project/session continuity using `project.el` and Emacs tab/session primitives remains compatible with this roadmap when it solves a concrete continuity problem;
- a custom notes/task database for project-aware literate work;
- replacing Company or the minibuffer completion stack solely to match example configurations;
- package-count minimization as a goal in itself;
- broad configuration schemas/orchestration frameworks whose principal consumer is the config itself;
- the closed custom visual PPTX editing spike as an implementation direction; separately tracked Office round-trip work should prefer existing conversion/rendering tools and thin Emacs integration.

## Historical design records

`docs/superpowers/specs/` and `docs/superpowers/plans/` preserve constraints, alternatives, migration details, and test rationale for individual changes. Some describe work that has already shipped and some contain implementation-specific instructions that should not be carried forward automatically.

If old plans disagree with the repository, the repository describes current behavior. If old plans disagree with this roadmap about future architectural direction, this roadmap is the current intent.

## When the modernization is done

Treat the standing modernization effort as complete when the package-lifecycle decision is resolved and no concrete structural cleanup remains open solely because of the modernization cycle.

At that point, the remaining GitHub issues are ordinary feature or maintenance work rather than continuation of a configuration rewrite.
