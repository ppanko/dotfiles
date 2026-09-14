# Unified Project-Aware Bash Design

## Purpose

Issue #20 will replace the split terminal model with one project-aware Bash workflow based on ordinary Emacs `shell-mode` / Comint on both GNU/Linux and native Windows.

The existing Windows shell behavior is the baseline. It already works well with the Rtools/MSYS2 Bash selected by `p3-platform.el`; the primary missing feature is project integration. GNU/Linux should adopt the same interaction model and retire the vterm-specific stack when the shared workflow satisfies the issue requirements.

## Design principles

1. **One user-facing shell workflow.** The same project-shell commands and buffer behavior should work on GNU/Linux and Windows.
2. **Platform code selects Bash; terminal code owns workflow.** `p3-platform.el` remains responsible for platform-specific executable/environment discovery. `p3-terminal.el` owns project-root resolution, shell-buffer identity, reuse, explicit extra sessions, switching, renaming, and killing.
3. **Use built-in shell-mode rather than emulate a terminal.** Normal Emacs selection, kill-ring, search, scrolling, and Comint editing are the intended interaction model.
4. **Preserve the Windows behavior that already works.** Keep Rtools/MSYS2 discovery, PATH mutation, CRLF stripping, UTF-8 process coding, and login-shell semantics unless a focused regression demonstrates a correction is needed.
5. **Keep project identity in `project.el`.** A project shell is keyed by normalized project root. Outside a project, use the current `default-directory`; do not create another project abstraction.
6. **Keep session state ephemeral and minimal.** At most one in-memory mapping is needed to identify the primary shell for a root. Explicit additional shells are ordinary extra buffers, not durable sessions.
7. **Remove superseded machinery.** If the shared `shell-mode` path meets the contract, remove vterm package ownership, vterm-specific commands/bindings/checks, the vterm-only Bash startup file, and ble.sh bootstrap/integration when no remaining workflow requires them.

## Architecture

### Platform layer: `lisp/p3-platform.el`

The platform layer exposes or configures the Bash environment used by Emacs.

- On Windows, retain the existing Rtools/MSYS2 discovery and PATH integration. The selected Bash remains the source of Unix command-line tools used by the configuration.
- On GNU/Linux, use the normal system Bash resolved through ordinary executable lookup/configuration.
- Platform-specific process-coding behavior remains platform-owned. In particular, Windows continues to install the shell-mode CRLF output filter and UTF-8 process coding.

No WSL, Git Bash, PowerShell, or new provider abstraction is introduced.

### Workflow layer: `lisp/p3-terminal.el`

Rename the conceptual surface from vterm-specific commands to shell-oriented project commands.

The workflow layer should provide:

- a root resolver that returns the current `project.el` project root or `default-directory`;
- a stable primary shell buffer name derived from root identity;
- one reusable primary shell per root;
- an explicit new-session path that creates another shell buffer without replacing the primary mapping;
- commands to open the primary shell in the current window or another window;
- commands to switch among live P3 shell buffers, rename a shell, and kill a shell;
- cleanup of stale primary mappings when buffers die, either lazily when looked up or through a small kill-buffer hook if simpler.

The workflow must launch ordinary `shell-mode` buffers and must not depend on vterm APIs.

### Configuration layer: `lisp/p3-config-terminal.el`

This module should become platform-neutral configuration for the project shell workflow.

It should:

- load the project-shell behavior on both supported platforms;
- call the existing platform shell configuration before creating shells;
- bind the same command surface on GNU/Linux and Windows;
- preserve the existing convenient `C-x C-u` entry point, but route it to the project-aware shell command on both platforms;
- expose the terminal command map on both platforms;
- keep only shell-mode/Comint configuration that is actually required by the shared workflow.

The GNU/Linux-only `use-package vterm` block and vterm keymaps should disappear once the replacement is complete.

## Shell creation semantics

Creating a project shell should be deterministic and small:

1. Resolve the root from `project.el`, falling back to `default-directory`.
2. Resolve the platform-configured Bash executable.
3. If the caller requested the primary shell and a live primary buffer already exists for that root, reuse it.
4. Otherwise create a shell buffer, set its `default-directory` to the resolved root before starting the process, and start `shell-mode` with the configured Bash.
5. Record the buffer as the root's primary only for the primary-shell path.
6. Explicit extra sessions use generated buffer names and remain ordinary shell buffers.

On Windows, shell creation must preserve the project working directory rather than resetting to the MSYS2 home directory. If this requires `CHERE_INVOKING=1` or an equivalent environment binding, apply it only around shell process creation and test the behavior directly.

## User-facing commands

Use generic names rather than preserving the vterm vocabulary. The final exact names may follow the repository's naming conventions, but the intended surface is:

- `p3/project-shell` — toggle/open the primary shell for the current project/root;
- `p3/project-shell-new` — create another shell for the current project/root;
- `p3/project-shell-switch` — select an existing P3 shell buffer;
- `p3/project-shell-other-window` — show the primary shell in another window;
- `p3/project-shell-rename` — rename the current P3 shell buffer;
- `p3/project-shell-kill` — kill the current or selected P3 shell buffer.

Avoid compatibility aliases for old `p3/vterm-*` names unless repository search finds a real consumer outside the terminal module/config/tests. The change should prefer removal over indefinite compatibility baggage.

## Interaction model

The workflow intentionally accepts `shell-mode`/Comint semantics instead of terminal-emulator semantics.

Supported behavior includes:

- normal Emacs selection and kill-ring copying;
- ordinary shell history and Comint editing;
- reliable scrolling/searching of prior output while processes continue printing;
- Bash builtins, shell scripts, Git CLI, `rg`, `find`, package-manager commands, and ordinary line-oriented interactive programs;
- multiple explicit shell buffers when needed.

Full-screen TUIs such as `htop`, `vim`, or terminal applications that require a complete PTY emulator are not requirements for this issue. Existing Emacs-native workflows remain preferred for Magit, ESS, Python tooling, and compilation.

## Error and fallback behavior

- If the platform Bash cannot be resolved, fail with a concise actionable `user-error` rather than silently launching an unrelated shell.
- If no project exists, use the local `default-directory`.
- If a remembered primary shell buffer is dead, discard the stale mapping and create a new one.
- A killed extra shell must not disturb the primary mapping unless it is the primary buffer itself.
- Existing Windows Rtools discovery warnings and fallback behavior remain platform-owned.
- Remote/TRAMP behavior is outside the scope of this issue unless the existing terminal command already promises it; do not accidentally reinterpret remote `default-directory` as a local shell root.

## Testing strategy

Tests should protect P3-owned behavior, not Emacs internals.

### Shared terminal tests

Add or update focused ERT coverage for:

- project-root resolution and `default-directory` fallback;
- stable primary buffer identity per normalized root;
- primary shell reuse;
- explicit extra-session creation without replacing the primary;
- switch/rename/kill behavior;
- stale-primary recovery;
- project root being installed as `default-directory` before shell startup;
- generic command-map/binding ownership with no vterm dependency.

Stub shell process creation where appropriate so most tests are deterministic and do not depend on a developer machine's interactive shell.

### Platform tests

Retain and extend native-Windows tests for:

- Rtools/MSYS2 Bash selection;
- login-shell argument behavior;
- CRLF stripping;
- UTF-8 process coding;
- project working-directory preservation during shell startup.

Add GNU/Linux coverage for selecting ordinary Bash and for the same project-shell workflow using the Linux platform path.

Do not test Comint's own editing/history implementation.

## Files expected to change

Primary files:

- `lisp/p3-terminal.el`
- `lisp/p3-config-terminal.el`
- `lisp/p3-platform.el` only if a small reusable Bash resolver or Windows working-directory fix is required
- `test/p3-config-terminal-test.el`
- `test/p3-platform-test.el`
- Windows/Linux CI loader lists only as needed for the changed test ownership

Likely removals:

- `vterm-bashrc`
- vterm/ble.sh-specific tests or assertions that no longer describe supported behavior

Avoid unrelated project/workspace refactors.

## Success criteria

The design is complete when one Bash-oriented project shell workflow behaves the same from the user's perspective on GNU/Linux and native Windows; Windows retains its existing working Rtools/MSYS2 shell semantics; Linux no longer depends on vterm for the normal shell path; project-root reuse and explicit extra sessions work on both platforms; and the implementation removes more vterm/ble.sh-specific machinery than it adds in replacement abstraction.
