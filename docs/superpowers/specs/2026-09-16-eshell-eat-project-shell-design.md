# Eshell + Eat project-shell design

Date: 2026-09-16

## Context

Issue #20 and PR #68 replaced the split vterm/Linux and shell-mode/Windows model with one project-aware Bash workflow built on `shell-mode`/Comint. PR #79 then restored richer prompt, history, input-highlighting, and history-search behavior on top of that architecture.

That architecture has now exposed two user-visible failures:

1. project-shell startup injects a multi-command Bash bootstrap after the shell prompt appears, so Bash emits multiple prompts during initialization;
2. full-screen terminal applications such as Codex are fundamentally incompatible with the line-oriented Comint display model, producing a broken interface rather than a usable TUI.

The first problem is a local bug. The second is architectural. Codex is now a concrete shell workflow requirement, so the earlier #20 non-goal that full-screen TUIs need not work is no longer valid.

A review of Eat also exposed two constraints that must be part of the design rather than deferred to implementation:

- an idle Eshell buffer has no persistent shell subprocess, so P3 cannot continue to define shell-session liveness by `get-buffer-process`;
- upstream `eat-eshell-mode` is a global Eshell integration. It advises Eshell process execution and currently relies on `stty` plus a `/usr/bin/env sh -c ...` wrapper for interactive external processes. Native-Windows compatibility therefore must be proven before the existing project-shell backend is removed.

## Goal

Provide one project-aware interactive shell workflow on GNU/Linux and native Windows that:

- feels like ordinary Emacs editing for normal command entry and shell output;
- remains project-aware and reuses one primary shell buffer per project;
- supports explicit additional sessions;
- preserves the useful rich-input behavior restored by PR #79;
- runs terminal-native interactive applications such as Codex correctly;
- avoids post-start prompt injection and prompt-spam regressions;
- remains small enough that project identity, terminal emulation, and platform discovery each have one clear owner.

## Decision

Use **Eshell as the primary interactive shell surface** and, if the native-Windows feasibility gate passes, **Eat's supported Eshell integration as the terminal-emulation layer for interactive external processes**.

Conceptually:

```text
p3/project-shell
      |
 semantic project identity
      |
 managed Eshell buffer
      |
 upstream eat-eshell-mode
      |
 interactive external process terminalization
      |
 Codex, htop, etc.
```

Eshell owns ordinary command entry, history, completion, editable output, and Emacs integration. Eat owns terminal emulation for interactive external subprocesses launched by Eshell.

This deliberately relaxes the earlier requirement that the *interactive shell language itself* must be Bash. Bash remains available as an external command and remains the interpreter for Bash scripts. The interactive shell is Eshell.

This design also accepts one upstream constraint explicitly: `eat-eshell-mode` is global. Enabling the supported mode affects Eshell generally, not only P3-created project-shell buffers. P3 must not depend on Eat's private `eat--eshell-local-mode` merely to fake buffer-local ownership.

## Feasibility gate before migration

Do not begin destructive migration from the current Comint/Bash project-shell backend until a focused spike proves that Eat's supported Eshell integration works under both supported operating systems.

The spike may be isolated test/configuration code and must not delete or replace the existing project-shell implementation.

### GNU/Linux spike

Verify with the repository's supported Emacs version that:

- Eat installs/loads through the existing package-management conventions;
- `eat-eshell-mode` enables successfully;
- `stty`, `/usr/bin/env`, and `sh` invocation work as Eat expects;
- a deterministic interactive terminal fixture receives raw input and terminal size correctly;
- alternate-screen entry/exit and cursor addressing render correctly;
- exiting the fixture returns cleanly to ordinary Eshell interaction.

### Native-Windows spike

Run the equivalent test under native Windows Emacs with the repository's normal Rtools/MSYS2 environment active. Explicitly verify:

- `stty` resolves from the configured external-tool environment;
- Eat's `/usr/bin/env sh -c ...` subprocess wrapper is actually executable from native Emacs rather than merely existing inside MSYS path semantics;
- terminal rows/columns and raw input are established correctly;
- alternate-screen and cursor-control output renders correctly;
- exit returns cleanly to Eshell;
- no additional WSL, Git Bash, PowerShell, or second terminal stack is required.

**Gate:** if the native-Windows spike fails at the supported Eat integration boundary, stop the migration and reconsider only the terminal-emulation backend. Do not partially migrate Linux, delete the existing Comint implementation, or patch Eat through private internals merely to force the architecture through.

## Why this design

### Compared with Comint + Bash

Comint provides excellent line-oriented shell interaction, but it is not a terminal emulator. Adding more prompt parsing, ANSI handling, or Bash initialization cannot make full-screen applications reliable. The current Codex failure is therefore not a bug that should be patched around inside `shell-mode`.

### Compared with a terminal-first shell

A terminal-first backend can run TUIs reliably, but it makes terminal semantics the default even for routine shell work. The configuration preference is the opposite: ordinary editing, selection, search, scrolling, and kill-ring behavior should remain native Emacs operations whenever possible.

### Compared with Eat visual-command mode

`eat-eshell-visual-command-mode` is more selective, but designated visual commands run in separate Eat buffers. The target UX is one project-shell workflow where invoking Codex from the prompt does not require switching to or managing a separate terminal buffer. Therefore the preferred design is in-place `eat-eshell-mode`, contingent on the feasibility gate.

## User-visible behavior

### Project shell command surface

Keep the current P3 commands and conceptual behavior:

- `p3/project-shell`: switch to the primary shell for the current project/directory, creating it when needed;
- invoking it again from the same project reuses that project's managed Eshell buffer;
- invoking it while already in that shell returns to the previous buffer, preserving the current toggle behavior;
- `p3/project-shell-new`: create an explicit additional shell for the same project;
- `p3/project-shell-switch`: choose among live P3 project-shell buffers;
- `p3/project-shell-other-window`: open/reuse the project shell in another ordinary Emacs window;
- rename and kill commands continue to operate on P3-managed shell buffers.

The P3 command surface should not expose Eat implementation details.

### Ordinary shell use

At the normal prompt, users get Eshell behavior:

- ordinary Emacs cursor movement and editing;
- normal region selection, kill-ring use, search, and scrolling;
- persistent Eshell history;
- Emacs completion facilities;
- readable long-running output in an Emacs buffer;
- project-local `default-directory` semantics;
- no special copy mode;
- no post-start Bash prompt bootstrap;
- one initial prompt rather than bootstrap-generated duplicates.

### Rich input UX

The migration must preserve the intent of the rich shell UX restored by PR #79 rather than regress to plain unassisted Eshell input.

At minimum:

- interactive command input has useful syntax/fontification feedback;
- invalid or unresolved external commands can be distinguished before or at submission where the chosen Eshell tooling supports that reliably;
- `C-r` provides a practical reverse-history search workflow rather than searching arbitrary buffer text;
- completion continues to use the user's normal Emacs completion UI;
- these features are platform-neutral rather than Linux-only decoration.

The implementation plan may choose Eshell-native facilities or one small maintained Eshell package for syntax highlighting. Do not reproduce Bash/Starship machinery solely to retain appearance.

### Interactive external applications

With `eat-eshell-mode`, interactive external Eshell processes are terminalized generally; P3 does not attempt to classify commands as TUIs itself.

The required user-visible contract is:

- ordinary external commands continue to work;
- terminal-native programs such as Codex can use cursor movement, raw input, terminal sizing, and alternate-screen behavior correctly;
- when such a process exits, the same Eshell buffer returns to normal editable prompt interaction;
- the user does not manually open or manage a second terminal buffer merely because a command is terminal-native.

## Project identity and lifecycle

`project.el` and the existing P3 semantic project-root logic remain authoritative. Do not introduce an Eshell-specific project abstraction.

### Managed-buffer liveness

Replace the current process-based session definition.

A P3 project shell is live when:

- its buffer is live;
- it is still a P3-managed project-shell buffer;
- it remains an Eshell buffer associated with the expected semantic project root.

A persistent external process is **not** required. An idle Eshell buffer with no child process is still the live primary shell for its project.

External-process state is separate from project-shell session state. Starting or exiting Codex must not make the P3 project-shell buffer disappear from or re-enter the session registry.

The existing ephemeral root-to-primary-buffer mapping may be retained. Stale mappings should be cleared either by a buffer-local kill hook or lazily when the buffer is no longer live. Explicit extra sessions remain outside the primary mapping.

Project shells created from Org notes with associated project context must continue to resolve the semantic project root rather than the Org-roam storage directory.

## Platform boundary

### GNU/Linux

No platform-specific shell executable is required for the primary interactive shell because Eshell is implemented in Emacs. External commands continue to resolve through the normal environment and `exec-path`.

### Native Windows

Retain `p3-platform.el` ownership of Rtools/MSYS2 discovery and PATH setup because external Unix-oriented tools, Git workflows, Bash scripts, Eat's `stty` requirement, and other command-line programs depend on that environment.

Do not configure the primary project shell by launching `bash.exe`. The Rtools/MSYS2 Bash path remains a platform capability for explicit Bash use and for other existing shell consumers, not the project-shell backend.

Do **not** remove or rewrite `p3/windows-configure-shell` merely because `p3/project-shell` moves to Eshell. That function still owns the repository's ordinary `M-x shell` behavior on native Windows. Project-shell migration should become independent of those Comint/MSYS details while preserving generic Shell-mode behavior unless a separate change intentionally removes it.

## Eat integration boundary

Use Eat's public supported integration rather than private functions.

Expected configuration:

- package/bootstrap owns Eat installation/loading;
- `eat-eshell-mode` is enabled deliberately as a global Eshell integration after the feasibility gate passes;
- P3 does not call `eat--eshell-local-mode` or other private helpers to create a pretend per-buffer mode;
- `eat-eshell-fallback-if-stty-not-available` is configured for deterministic fallback to plain Eshell, not the upstream interactive `ask` default;
- project-shell creation does not perform package installation or network work synchronously.

If Eat is unavailable at runtime, ordinary Eshell remains usable. Terminalized interactive-process capability is then unavailable and should be surfaced through a concise warning/error when relevant, not through repeated yes/no prompts.

## Prompt and appearance

Do not reproduce the current Starship/Bash bootstrap in Eshell.

The shell prompt should be implemented through Eshell-native prompt configuration. It may retain useful information from the tracked Starship prompt—project-relative/current directory, inexpensive Git state, and previous command status—but should not repeatedly shell out merely to mimic Starship exactly.

Prompt behavior must satisfy:

- one visible prompt on startup;
- no injected initialization commands in shell history or output;
- no dependency on Bash prompt hooks;
- no terminal-specific escape sequences required for the normal prompt;
- prompt computation remains cheap enough not to make shell interaction sluggish.

The tracked `templates/p3-starship.toml` is removed only after repository search confirms no remaining supported workflow consumes it.

## History and completion

Use Eshell's own history as the project-shell interactive history authority rather than sharing Bash's `HISTFILE`.

Expected behavior:

- history survives across Emacs sessions using Eshell's normal persistence mechanism;
- duplicate handling is sensible for interactive use;
- P3 bootstrap/implementation details cannot appear in history because there is no post-start shell bootstrap;
- `C-r` searches command history rather than arbitrary scrollback;
- completion uses Eshell/Emacs completion facilities and the existing completion UI;
- terminalized process execution does not permanently replace ordinary editing/completion behavior after the process exits.

Bash history remains Bash's concern when the user explicitly launches Bash.

## Configuration ownership

Recommended responsibility split:

- `p3-project.el`: project identity and semantic root resolution;
- `p3-platform.el`: OS-specific tool discovery/environment, including Rtools/MSYS2 and the existing generic Windows `M-x shell` setup;
- `p3-terminal.el`: P3 project-shell buffer lifecycle, naming, reuse, switching, extras, prompt/history UX, and thin Eshell setup helpers;
- `p3-config-terminal.el`: Eat package ownership, supported global Eshell integration, and global P3 key bindings;
- Eshell: command language, prompt loop, history, completion, and normal buffer interaction;
- Eat: terminal emulation for interactive external Eshell processes.

Do not add another project identity layer, terminal multiplexer, or session database.

## Migration sequence

Implementation must proceed in this order so an unsupported backend does not strand the repository between architectures:

1. add the cross-platform Eat + Eshell feasibility spike without replacing production project-shell behavior;
2. require the Linux and native-Windows spike gates to pass;
3. add TDD coverage for Eshell-managed P3 buffer lifecycle and project reuse;
4. migrate P3 project-shell creation/session semantics from process-backed Shell-mode buffers to managed Eshell buffers;
5. restore rich input UX, prompt, history, and completion behavior in the Eshell path;
6. enable/configure the supported Eat integration and deterministic fallback;
7. run deterministic terminal-emulation integration tests plus manual Codex smoke tests;
8. only after both platforms pass, remove project-shell-specific Comint/Bash/Starship machinery that is no longer consumed.

Do not ship a Linux-only partial migration.

## Cleanup after verification

Once the Eshell + Eat path is verified on both supported platforms, remove behavior that exists only for the displaced Comint/Bash **project-shell** implementation:

- `p3/project-shell-prompt-init-command` and post-launch Bash prompt injection;
- P3 project-shell Comint prompt recognition;
- P3 project-shell-specific `shell-mode` input/highlighting setup;
- project-shell Bash `HISTFILE` / `histappend` management;
- project-shell rich-terminfo probing added for Comint/Starship;
- tracked Starship configuration only if repository search confirms it is unused elsewhere;
- tests that assert displaced project-shell implementation details rather than the user-visible contract.

Keep generic `shell-mode`, ESS/Comint consumers, and native-Windows `p3/windows-configure-shell` behavior unless separately proven unused and intentionally removed.

## Failure handling

### Eat missing or unavailable

P3 project shells still open as ordinary Eshell buffers. The configuration should issue at most a concise capability warning rather than blocking shell creation.

### `stty` unavailable

Configure Eat to fall back deterministically to plain Eshell. Do not use an interactive yes/no fallback prompt in normal project-shell execution.

### Native-Windows integration failure

Fail the feasibility/migration gate. Keep the current working project-shell backend intact and reassess the terminal-emulation backend. Do not add WSL or another parallel shell stack automatically.

### External process exits abnormally

Return to the same managed Eshell project-shell buffer whenever Eshell/Eat can recover normally. Process failure must not invalidate the P3 session mapping merely because there is no longer a child process.

## Testing

Implementation follows TDD. Regression coverage should test P3 behavior and the terminal contract rather than private Eat internals.

### Feasibility spike tests

On GNU/Linux and native Windows:

- Eat package loads;
- supported `eat-eshell-mode` enables;
- required helper commands/path semantics work;
- deterministic terminal fixture gets a terminal-sized interactive process;
- raw/interactive input reaches the child;
- cursor-addressing output is interpreted rather than leaked literally;
- alternate-screen enter/exit is handled;
- resize/rows/columns behavior is correct enough for a TUI;
- fixture exit returns to ordinary Eshell interaction.

The native-Windows spike must pass before production migration starts.

### Platform-neutral P3 tests

- project shell resolves the same semantic project root as other P3 project-aware processes;
- one primary **buffer** is reused per project while idle;
- absence of a child process does not make an Eshell project shell stale;
- an explicit extra session creates a distinct managed Eshell buffer;
- killing a primary buffer clears or lazily invalidates its mapping;
- toggle/other-window/switch/rename/kill behavior remains correct;
- project shell is Eshell-based, not `shell-mode`/Comint-based;
- Org-associated project context routes to the associated project rather than the note directory;
- startup contains no P3 Bash bootstrap and does not generate duplicate prompts;
- prompt/history setup is Eshell-native;
- `C-r` invokes history-oriented search;
- rich input/fontification configuration is active;
- absence of Eat leaves ordinary Eshell usable without an interactive fallback prompt.

### Deterministic terminal-contract integration tests

Use a small local fixture rather than Codex in CI. It should exercise:

- alternate-screen entry and restoration;
- cursor movement/addressing;
- raw key/input handling;
- reported terminal dimensions and resize behavior;
- ordinary process exit and nonzero exit;
- return to a normal Eshell prompt without raw terminal escape leakage.

Run this contract on both Linux and native Windows.

### Manual acceptance smoke

On both supported platforms, when Codex is installed/configured:

- launch `codex` from the P3 project Eshell;
- interact with the full-screen UI, including typing, movement, scrolling where applicable, and resize;
- exit Codex;
- confirm normal Eshell editing/history/completion resumes in the same project-shell buffer.

Codex authentication/network availability is not a CI dependency.

## Acceptance criteria

- The Eat + Eshell feasibility spike passes on GNU/Linux and native Windows before migration removes the existing backend.
- One P3 project-shell command surface works on both supported platforms.
- The primary shell surface is a managed Eshell buffer and behaves like a normal Emacs buffer for routine work.
- Repeated invocation reuses one live primary shell **buffer** per semantic project root even when no external process is running.
- Explicit additional project-shell buffers remain supported.
- Org-associated project context still routes shells to the associated project rather than the note directory.
- Startup shows one prompt and no P3 Bash-bootstrap commands or duplicate prompts.
- Syntax/input feedback, practical `C-r` history search, completion, selection, search, scrolling, and kill-ring behavior remain useful and platform-neutral.
- External commands inherit the expected project directory and platform environment.
- Native Windows retains Rtools/MSYS2 external-tool discovery and ordinary `M-x shell` support without requiring the project shell itself to be Bash.
- Supported Eat integration, not private Eat internals, supplies terminal emulation.
- `stty`/Eat failure falls back deterministically to plain Eshell without surprise yes/no prompts.
- The deterministic terminal fixture passes alternate-screen, cursor, raw-input, terminal-size/resize, and clean-return tests on Linux and native Windows.
- Codex works in a manual smoke test from the same project-shell workflow on both supported platforms when available.
- Exiting a terminal-native process returns to normal Eshell editing without invalidating the P3 project-shell session.
- No separate user-facing terminal command is required merely to run a TUI.
- Obsolete project-shell-specific Comint/Bash prompt/history/Starship/terminfo machinery is removed only after both-platform verification.
- Existing non-project-shell Comint consumers and generic native-Windows Shell-mode behavior remain unaffected.

## Non-goals

- Reimplement Bash semantics in Eshell.
- Make every Bash one-liner valid Eshell syntax.
- Build command-specific TUI detection in P3.
- Patch or depend on Eat private internals to simulate buffer-local integration.
- Replace ESS, Python REPLs, Magit, compilation mode, or other purpose-built Emacs workflows.
- Build a terminal multiplexer or persistent session database.
- Add WSL, PowerShell, Git Bash, or another parallel shell stack solely for symmetry.
- Preserve the current Starship implementation for its own sake.

## Migration principle

This change should replace the failed project-shell architectural assumption rather than accumulate another compatibility layer. The target is one project-shell workflow: P3 manages project-aware Eshell buffers; Eshell owns normal interaction; supported Eat integration supplies terminal semantics for interactive external processes. The existing Comint/Bash project-shell implementation remains intact until that complete contract is demonstrated on both supported platforms.