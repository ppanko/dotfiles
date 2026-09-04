# Startup/Tangle Cache Design

## Goal

Stop tangling the entire literate Emacs configuration on every startup while preserving `config.org` as the sole authoritative configuration source and keeping startup reliable after edits, pulls, checkouts, and merges.

The generated `config.el` remains an ignored local cache. Normal startup should load that cache directly when it was generated from the exact current contents of `config.org`, rebuild it only when the cache is missing or does not match the source, and never require a tracked generated configuration file.

## Current behavior and problem

`init.el` currently requires Org and Babel during bootstrap, tangles `config.org` to `config.el` on every startup, and then loads the generated file. This guarantees freshness, but it also performs the full 124-block tangle and rewrites `config.el` even when nothing has changed.

That coupling makes startup do build work unconditionally. It also makes the generated file behave less like a cache and more like an obligatory intermediate artifact, despite being ignored by Git and having no independent authority.

## Architecture

Introduce `lisp/p3-config-loader.el` as the focused owner of the generated-config lifecycle. The loader should be usable independently of the full Emacs configuration so its cache behavior can be tested without invoking package bootstrap or evaluating the real generated configuration.

`p3-config-loader.el` will own:

- `p3/config-source`, pointing to `config.org`;
- `p3/config-generated`, pointing to ignored `config.el`;
- source fingerprint generation and cache fingerprint reading;
- `p3/config-cache-stale-p`, which decides whether regeneration is needed;
- `p3/config-build`, which explicitly regenerates and validates the cache;
- `p3/config-load-generated`, which loads the exact generated source file without performing freshness logic; and
- `p3/config-load`, the normal startup entry point that rebuilds only when required and then loads the cache.

Startup uses `p3/config-load`. Interactive reload uses `p3/config-build` followed by `p3/config-load-generated`, so reload performs exactly one rebuild and one load.

`init.el` remains responsible for bootstrap sequencing only. After adding `lisp/` to `load-path` and establishing the early `p3-project` project semantics, it requires `p3-config-loader` and calls `p3/config-load`. The loader decides whether a build is required.

`p3-core.el` retains the user-facing visit/reload commands and depends on `p3-config-loader` for build/load behavior rather than owning the generated-file lifecycle itself.

## Source-of-truth contract

`config.org` remains the only authoritative configuration source.

`config.el` remains ignored by Git and must not be edited as source. It is a disposable local cache that can always be reconstructed from `config.org`.

This PR will not begin tracking `config.el`, add a second canonical representation of the configuration, or introduce a sidecar manifest.

## Freshness contract

Freshness is content-based, not timestamp-based.

The loader computes a SHA-256 fingerprint from the exact current contents of `config.org`. A successful build records that fingerprint in a generated comment at the top of `config.el`, for example:

```text
;; p3-config-source-sha256: <digest>
```

The generated cache is stale when any of the following is true:

1. `config.el` does not exist;
2. the expected fingerprint header is missing or malformed; or
3. the recorded fingerprint does not equal the SHA-256 fingerprint of the current `config.org` contents.

A cache is current only when the fingerprints match exactly. Filesystem modification times do not participate in this decision.

This keeps checkouts, pulls, merges, restored timestamps, and same-timestamp edits correct without introducing watchers or persistent metadata. Hashing a configuration file of this size is small startup work and does not require Org or Babel.

If someone manually edits the ignored `config.el`, the embedded fingerprint does not make that edit authoritative. Manual cache edits are unsupported; `p3/config-build` reconstructs the cache from `config.org`.

## Tangle-boundary contract

`config.el` is a single generated Emacs Lisp artifact. The build must not permit `config.org` to redirect individual blocks to unrelated tangle destinations.

Before tangling, the loader must validate the effective Babel tangle configuration and reject explicit per-file, property-level, or block-level `:tangle` destinations that would escape the single-cache contract. This validation occurs before any tangle writes are performed.

The actual tangle must:

- include only `emacs-lisp` source blocks;
- use one staged file in the same directory as `config.el` as the intended output; and
- verify that the tangler reports only that intended staged output.

The current `config.org` does not depend on custom `:tangle` destinations. If a future configuration genuinely needs multiple generated artifacts, that is a separate design decision rather than something the startup loader should infer implicitly.

## Build contract

Expose `p3/config-build` as the explicit rebuild command.

A build should:

1. compute the SHA-256 fingerprint of `config.org`;
2. load Org/Babel tangling support lazily;
3. validate the single-target tangle contract before any tangle writes occur;
4. tangle only `emacs-lisp` blocks from `config.org` into a temporary file in the same configuration directory;
5. verify that the tangler produced only the intended staged file;
6. insert the source-fingerprint comment into the staged file;
7. verify that the staged file is syntactically readable Emacs Lisp without evaluating it;
8. replace `config.el` with one same-directory `rename-file` operation that permits replacing the existing destination; and
9. return the generated file path.

Using a staged same-directory file protects the previous generated cache from interrupted tangling, malformed generated Lisp, and partial replacement. The implementation must not delete `config.el` before renaming the staged file over it.

Runtime errors inside otherwise readable configuration are intentionally not part of build validation; they remain load-time errors.

The temporary file must be cleaned up on both success and failure when it still exists. Replacement occurs only after tangling and syntax validation succeed.

The build command may report a concise interactive success message, but startup-triggered rebuilds should remain quiet unless an error occurs.

## Load and startup contract

`p3/config-load-generated` loads `p3/config-generated` with `load-file`. It loads that exact `.el` file and does no freshness checking or rebuilding; an unrelated or stale `config.elc` must never enter generated-cache selection.

`p3/config-load` performs the normal startup path:

1. compare the embedded cache fingerprint with the current source fingerprint;
2. call `p3/config-build` only when the cache is missing or mismatched; and
3. call `p3/config-load-generated`.

When the cache fingerprint matches, normal startup must not require `org`, `ob-tangle`, or call the tangler as part of the loader path.

A fresh clone or a machine with no generated cache tangles once on first startup, then uses the generated cache on subsequent startups until the contents of `config.org` change.

The startup ordering established by the project foundation remains intact: `p3-project` must still be loaded before the literate configuration, so project detection cannot be cached with competing semantics before the config runs.

## Reload workflow

The existing user-facing `p3/config-reload` command should preserve its current practical meaning: edits to `config.org` are rebuilt and then loaded into the current Emacs session.

`p3/config-reload` therefore calls `p3/config-build` unconditionally and, only after that succeeds, calls `p3/config-load-generated`. It does not call the freshness-aware startup entry point. This guarantees exactly one rebuild per reload request.

`p3/config-visit` continues to open `config.org`.

Existing keybindings for visiting and reloading the configuration remain unchanged.

## Failure behavior

A tangle, tangle-contract, fingerprint-insertion, or syntax-validation failure occurs before cache replacement. Such a failure must leave both the running Emacs session and the previous `config.el` untouched, clean up the staged file, and propagate the error. Startup must not silently fall back to a cache whose fingerprint does not match the authoritative source.

A load-time error is different. Once a validated `config.el` begins evaluating, Emacs Lisp configuration loading is not transactional. A runtime error may occur after earlier forms have already modified the current Emacs session. The loader must propagate that error normally and must not claim to roll back those effects.

Similarly, when a rebuild succeeds and replaces `config.el` but loading that new cache then fails at runtime, the new syntactically valid cache remains on disk. The loader does not attempt to restore the previous cache automatically or reinterpret a runtime failure as a stale-cache failure.

If a current fingerprint-matching `config.el` cannot be loaded, the load error propagates normally. The loader should not automatically rebuild merely because evaluation failed; that would obscure the distinction between generation correctness and runtime configuration behavior.

## Package/bootstrap implications

This PR changes only the configuration build/load boundary. It does not redesign package installation or `use-package` bootstrap.

Org and `ob-tangle` are no longer unconditional bootstrap dependencies of the loader. They are required only when a build is needed. The current-cache path uses only ordinary file I/O, hashing, fingerprint parsing, and `load-file`.

The literate configuration may still load Org later for normal Org functionality; this PR does not attempt to defer or reorganize that package configuration.

## Tests

Add focused ERT coverage for `p3-config-loader.el` that establishes:

1. a missing generated cache is stale;
2. a cache with a missing or malformed fingerprint is stale;
3. a cache whose recorded fingerprint differs from `config.org` is stale regardless of file modification times;
4. a cache with a matching fingerprint is current regardless of file modification times;
5. a current cache loads without invoking the tangler or requiring Org/Babel through the loader;
6. a missing or mismatched cache rebuilds before loading;
7. explicit `p3/config-build` always rebuilds regardless of the current fingerprint;
8. `p3/config-reload` performs exactly one explicit build followed by a direct generated-file load;
9. explicit alternate `:tangle` destinations are rejected before tangling;
10. only `emacs-lisp` blocks are admitted to the generated cache;
11. a tangle failure does not replace an existing generated cache;
12. syntactically malformed tangled output does not replace an existing generated cache;
13. temporary build artifacts are cleaned up after success and failure;
14. successful replacement overwrites an existing `config.el` through the staged rename path;
15. `p3/config-load-generated` uses the exact `.el` cache even if a `config.elc` exists;
16. `init.el` loads `p3-project` before `p3-config-loader` loads the literate configuration; and
17. the real `config.org` still tangles to syntactically readable Emacs Lisp under the single-target/emacs-lisp-only contract.

Tests should use temporary source/generated files for cache lifecycle behavior and should not load the real generated configuration as part of unit tests.

The existing full ERT suite remains the regression gate. `p3-config-loader.el` should be byte-compiled with warnings treated as errors.

## CI and Windows contract

The normal Ubuntu workflow should add `p3-config-loader.el` to byte-compilation and load its ERT tests. CI should continue freshly tangling the real `config.org` to a temporary file and checking that the result is readable and respects the single-target contract. Because `config.el` remains untracked, CI should not compare the repository against a committed generated file.

The existing native-Windows workflow should be extended narrowly to exercise the filesystem behavior introduced by this PR. It must verify that, with an existing generated cache:

1. a staged same-directory file can replace `config.el` through the loader's rename path;
2. the resulting `config.el` contains the expected new contents/fingerprint; and
3. the staged temporary file no longer exists afterward.

No new workflow, matrix, cache service, or diagnostic machinery is required. The Windows addition belongs in the existing platform workflow and should run only when the relevant loader/test files change under that workflow's normal path filtering.

## Non-goals

This PR will not:

- track `config.el` in Git;
- make `config.el` a second source of truth;
- remove `config.org`;
- use modification times for cache validity;
- add a sidecar manifest, watcher, Makefile, or external build tool;
- byte-compile the generated `config.el`;
- evaluate generated code as part of build validation;
- make configuration evaluation transactional or add runtime rollback machinery;
- support multiple independent tangle destinations from `config.org`;
- reorganize `config.org` into package modules;
- redesign package bootstrap or package installation;
- alter project semantics from PR #10;
- change completion, ESS, Python, Org, terminal, or window behavior; or
- add background rebuilding.

The later modules-vs-functionality PR remains responsible for broader configuration decomposition.
