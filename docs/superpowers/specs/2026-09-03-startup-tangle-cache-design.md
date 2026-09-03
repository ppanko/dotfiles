# Startup/Tangle Cache Design

## Goal

Stop tangling the entire literate Emacs configuration on every startup while preserving `config.org` as the sole authoritative configuration source and keeping startup reliable after edits, pulls, checkouts, and merges.

The generated `config.el` remains an ignored local cache. Normal startup should load that cache directly when it is current, rebuild it only when it is missing or stale, and never require a tracked generated configuration file.

## Current behavior and problem

`init.el` currently requires Org and Babel during bootstrap, tangles `config.org` to `config.el` on every startup, and then loads the generated file. This guarantees freshness, but it also performs the full 124-block tangle and rewrites `config.el` even when nothing has changed.

That coupling makes startup do build work unconditionally. It also makes the generated file behave less like a cache and more like an obligatory intermediate artifact, despite being ignored by Git and having no independent authority.

## Architecture

Introduce `lisp/p3-config-loader.el` as the focused owner of the generated-config lifecycle. The loader should be usable independently of the full Emacs configuration so its cache behavior can be tested without invoking package bootstrap or evaluating `config.org`.

`p3-config-loader.el` will own:

- `p3/config-source`, pointing to `config.org`;
- `p3/config-generated`, pointing to ignored `config.el`;
- freshness detection for the generated cache;
- explicit cache rebuilding;
- conditional cache rebuilding for startup;
- loading the generated configuration.

`init.el` remains responsible for bootstrap sequencing only. After adding `lisp/` to `load-path` and establishing the early `p3-project` project semantics, it requires `p3-config-loader` and asks it to load the configuration. The loader decides whether a build is required.

`p3-core.el` retains the user-facing visit/reload commands, but delegates build/load behavior to the loader rather than owning the generated-file lifecycle itself.

## Source-of-truth contract

`config.org` remains the only authoritative configuration source.

`config.el` remains ignored by Git and must not be edited as source. It is a disposable local cache that can always be reconstructed from `config.org`.

This PR will not begin tracking `config.el`, add a second canonical representation of the configuration, or introduce a generated-file manifest.

## Freshness contract

The generated cache is considered stale when either:

1. `config.el` does not exist; or
2. `config.org` is newer than `config.el` according to normal file modification times.

A current cache is loaded without tangling.

This deliberately uses the filesystem timestamp relationship rather than hashes, sidecar metadata, file watchers, or a build system. Git checkouts and pulls that update `config.org` naturally refresh its modification time, causing the next startup to rebuild the cache.

The design assumes `config.el` is not manually edited. If someone manually changes the ignored cache and makes it newer than `config.org`, that cache may be loaded until the source changes or an explicit rebuild is requested. That is acceptable because the generated file is explicitly non-authoritative.

## Build contract

Expose `p3/config-build` as the explicit rebuild command.

A build should:

1. load Org/Babel tangling support lazily;
2. tangle `config.org` into a temporary file in the same configuration directory;
3. replace `config.el` only after the tangle succeeds; and
4. return the generated file path.

Using a temporary file protects the last valid generated cache from a failed or interrupted tangle. The final replacement should occur only after `org-babel-tangle-file` completes successfully.

The temporary file must be cleaned up on both success and failure.

The build command may report a concise interactive success message, but startup-triggered rebuilds should remain quiet unless an error occurs.

## Load and startup contract

Expose a loader entry point that performs the normal startup path:

1. check whether the generated cache is missing or stale;
2. call `p3/config-build` only when rebuilding is required; and
3. load `config.el`.

When the cache is current, normal startup must not require `org`, `ob-tangle`, or call `org-babel-tangle-file` as part of the loader path.

A fresh clone or a machine with no generated cache tangles once on first startup, then uses the generated cache on subsequent startups until `config.org` changes.

The startup ordering established by the project foundation remains intact: `p3-project` must still be loaded before the literate configuration, so project detection cannot be cached with competing semantics before the config runs.

## Reload workflow

The existing user-facing `p3/config-reload` command should preserve its current practical meaning: edits to `config.org` are rebuilt and then loaded into the current Emacs session.

`p3/config-reload` therefore must force an explicit `p3/config-build` before loading, rather than relying only on modification-time freshness. This keeps the edit -> reload workflow deterministic even in unusual timestamp situations.

`p3/config-visit` continues to open `config.org`.

Existing keybindings for visiting and reloading the configuration remain unchanged.

## Failure behavior

If a startup-triggered rebuild fails, startup should surface the build error rather than silently load the older cache. The previous valid `config.el` should remain on disk because rebuilding occurs through a temporary file, but stale configuration must not be silently substituted for the authoritative source.

If an interactive `p3/config-build` or `p3/config-reload` fails, the current Emacs session remains as it was before the attempted reload, and the last valid generated cache remains available for later recovery.

If `config.el` is current but cannot be loaded, the load error should propagate normally. The loader should not automatically rebuild merely because evaluation of a current generated file failed; that would obscure the distinction between stale generation and a runtime configuration error.

## Package/bootstrap implications

This PR changes only the configuration build/load boundary. It does not redesign package installation or `use-package` bootstrap.

Org and `ob-tangle` should no longer be unconditional bootstrap dependencies of the loader. They are required only when a build is needed. The literate configuration may still load Org later for normal Org functionality; this PR does not attempt to defer or reorganize that package configuration.

## Tests

Add focused ERT coverage for `p3-config-loader.el` that establishes:

1. a missing generated cache is stale;
2. an older generated cache is stale;
3. a generated cache newer than or equal to the source is current;
4. a current cache loads without invoking the tangler;
5. a missing or stale cache rebuilds before loading;
6. explicit `p3/config-build` always rebuilds regardless of timestamps;
7. `p3/config-reload` always rebuilds before loading;
8. a failed build does not replace an existing valid generated cache;
9. temporary build artifacts are cleaned up after success and failure;
10. the loader does not require Org/Babel on the current-cache path;
11. `init.el` loads `p3-project` before `p3-config-loader` loads the literate configuration;
12. the real `config.org` still tangles to syntactically readable Emacs Lisp.

Tests should use temporary source/generated files for cache lifecycle behavior and should not load the real generated configuration as part of unit tests.

The existing full ERT suite remains the regression gate. `p3-config-loader.el` should be byte-compiled with warnings treated as errors.

## CI

The normal Ubuntu workflow should add `p3-config-loader.el` to byte-compilation and load its ERT tests.

CI should continue freshly tangling the real `config.org` to a temporary file and checking that the result is readable. Because `config.el` remains untracked, CI should not compare the repository against a committed generated file.

No new workflow, matrix, cache service, or diagnostic machinery is required. Windows-specific behavior is not changed by this PR, so the existing Windows project/platform workflow does not need a new startup-cache test unless implementation reveals a Windows-specific filesystem issue.

## Non-goals

This PR will not:

- track `config.el` in Git;
- make `config.el` a second source of truth;
- remove `config.org`;
- introduce hashes, manifests, watchers, Makefiles, or external build tooling;
- byte-compile the generated `config.el`;
- reorganize `config.org` into package modules;
- redesign package bootstrap or package installation;
- alter project semantics from PR #10;
- change completion, ESS, Python, Org, terminal, or window behavior;
- add background rebuilding.

The later modules-vs-functionality PR remains responsible for broader configuration decomposition.