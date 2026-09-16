# Eshell + Eat project-shell design

Date: 2026-09-16

## Context

Issue #20 and PR #68 replaced the split vterm/Linux and shell-mode/Windows model with one project-aware Bash workflow built on `shell-mode`/Comint. PR #79 then restored richer prompt, history, and input behavior on top of that architecture.

That architecture has now exposed two user-visible failures:

1. project-shell startup injects a multi-command Bash bootstrap after the shell prompt appears, so Bash emits multiple prompts during initialization;
2. full-screen terminal applications such as Codex are fundamentally incompatible with the line-oriented Comint display model, producing a broken interface rather than a usable TUI.

The first problem is a local bug. The second is architectural. Codex is now a concrete shell workflow requirement, so the earlier #20 non-goal that full-screen TUIs need not work is no longer valid.

## Goal

Provide one project-aware interactive shell workflow on GNU/Linux and native Windows that:

- feels like ordinary Emacs editing for normal command entry and shell output;
- remains project-aware and reuses one primary shell per project;
- supports explicit additional sessions;
- runs terminal-native interactive applications such as Codex correctly;
- does not require a captive terminal interaction model for ordinary shell use;
- avoids post-start prompt injection and prompt-spam regressions;
- remains small enough that project identity, terminal emulation, and platform discovery each have one clear owner.

## Decision

Use **Eshell as the primary interactive shell surface** and **Eat as its terminal-emulation layer**.

Conceptually:

```text
p3/project-shell
      |
 project identity
      |
    Eshell
      |
 eat-eshell-mode
   /       \
normal     terminal-native
commands   applications
   |            |
Emacs-editable  Eat PTY/terminal
input/output    emulation
                |
          Codex, htop, etc.
```

Eshell owns ordinary command entry, history, completion, editable output, and Emacs integration. Eat is not the primary shell UI; it supplies terminal semantics when a subprocess actually needs them.

This deliberately relaxes the earlier requirement that the *interactive shell language itself* must be Bash. Bash remains available as an external command and remains the interpreter for Bash scripts. The interactive shell is Eshell.

## Why this design

### Compared with Comint + Bash

Comint provides excellent line-oriented shell interaction, but it is not a terminal emulator. Adding more prompt parsing, ANSI handling, or Bash initialization cannot make full-screen applications reliable. The current Codex failure is therefore not a bug that should be patched around inside `shell-mode`.

### Compared with Ghostel as the primary shell

Ghostel can provide both a true terminal and an Emacs-editable line mode, and it remains a viable alternative. However, the configuration already prefers ordinary Emacs buffer semantics for routine shell work. Eshell is the native expression of that preference and avoids making terminal emulation the default execution model when it is unnecessary.

### Compared with `term` / `ansi-term`

Built-in terminal modes can run TUIs, but they reintroduce the terminal-first editing and copy/navigation compromises that motivated removal of vterm. Eat is used only where terminal semantics are needed while Eshell remains the normal surface.

## User-visible behavior

### Project shell command surface

Keep the current P3 commands and conceptual behavior:

- `p3/project-shell`: switch to the primary shell for the current project/directory, creating it when needed;
- invoking it again from the same project reuses the same live shell;
- invoking it while already in that shell returns to the previous buffer, preserving the current toggle behavior;
- `p3/project-shell-new`: create an explicit additional shell for the same project;
- `p3/project-shell-switch`: choose among live P3 project shells;
- `p3/project-shell-other-window`: open/reuse the project shell in another ordinary Emacs window;
- rename and kill commands continue to operate on P3-managed shell buffers.

The command surface should not expose whether Eat is currently involved.

### Ordinary shell use

At the normal prompt, users get Eshell behavior:

- ordinary Emacs cursor movement and editing;
- normal region selection, kill-ring use, search, and scrolling;
- Eshell history and completion;
- readable long-running output in an Emacs buffer;
- project-local `default-directory` semantics;
- no special copy mode;
- no post-start Bash prompt bootstrap;
- no duplicate startup prompts.

### Terminal-native applications

Eat integration must make terminal-native subprocesses usable from the same Eshell buffer. At minimum the design must support Codex as the acceptance-case TUI.

When a program requires terminal semantics, Eat supplies them. When it exits, control returns to the normal Eshell interaction model. The user should not need to manually open another terminal buffer or choose a different command solely because a program uses cursor addressing or alternate-screen behavior.

## Platform boundary

### GNU/Linux

No platform-specific shell executable is required for the primary interactive shell because Eshell is implemented in Emacs. External commands continue to resolve through the normal environment and `exec-path`.

### Native Windows

Retain `p3-platform.el` ownership of Rtools/MSYS2 discovery and PATH setup because external Unix-oriented tools, Git workflows, Bash scripts, and other command-line programs still depend on that environment.

However, do not configure the primary project shell by launching `bash.exe`. The Rtools/MSYS2 Bash path remains a platform capability that external commands and explicit Bash invocations can use, not the project-shell backend.

Any existing Windows configuration that exists solely to make Comint talk correctly to MSYS Bash—such as CRLF filtering, `explicit-bash.exe-args`, shell-specific directory resynchronization, or `shell-mode` process coding—should be removed from the project-shell path when it no longer has another consumer. Rtools discovery and PATH/tool exposure remain.

## Prompt and appearance

Do not reproduce the current Starship/Bash bootstrap in Eshell.

The shell prompt should be implemented through Eshell-native prompt configuration. It may retain the useful information from the tracked Starship prompt—project-relative/current directory, Git state when inexpensive, previous command success/error indication—but it should not shell out repeatedly merely to mimic Starship exactly.

Prompt behavior should satisfy these constraints:

- one visible prompt on startup;
- no injected initialization commands in shell history or output;
- no dependency on Bash prompt hooks;
- no terminal-specific escape sequences required for the normal prompt;
- prompt computation must remain cheap enough not to make shell interaction sluggish.

The existing `templates/p3-starship.toml` should be removed if no remaining supported workflow consumes it.

## History and completion

Use Eshell's own history as the interactive history authority rather than sharing Bash's `HISTFILE`.

Expected behavior:

- history survives across Emacs sessions using the normal Eshell history mechanism;
- duplicate handling should remain sensible for interactive use;
- P3 bootstrap or implementation details never appear in history because there is no post-start shell bootstrap;
- completion should use Eshell/Emacs completion facilities;
- Eat must not permanently replace the ordinary completion/editing behavior after a terminal-native program exits.

Bash history remains Bash's concern when the user explicitly launches Bash.

## Project identity and lifecycle

`project.el` and the existing P3 semantic project-root logic remain authoritative. Do not introduce an Eshell-specific project abstraction.

The current ephemeral mapping from project root to primary shell buffer may be retained if it remains the simplest reliable way to guarantee primary-shell reuse. The buffer predicate/lifecycle layer should be backend-neutral in naming where practical; callers should care that a buffer is a P3 project shell, not that it happens to be Eshell.

Project shells created from Org notes with associated project context must continue to resolve the semantic project root rather than the Org-roam storage directory.

## Configuration ownership

Recommended responsibility split:

- `p3-project.el`: project identity and semantic root resolution;
- `p3-platform.el`: OS-specific tool discovery/environment, including Rtools/MSYS2 on Windows;
- `p3-terminal.el`: P3 project-shell lifecycle, naming, reuse, switching, extra sessions, and thin Eshell setup helpers;
- `p3-config-terminal.el`: package ownership/configuration for Eat plus global key bindings;
- Eshell/Eat themselves: command language, history/completion, PTY and terminal emulation.

Do not add another session manager or terminal abstraction layer.

## Cleanup

Once the Eshell + Eat path is verified, remove behavior that exists only for the displaced Comint/Bash project shell:

- `p3/project-shell-prompt-init-command` and all post-launch Bash prompt injection;
- Comint-specific prompt recognition for P3 project shells;
- project-shell-specific `shell-mode` input/highlighting configuration;
- Bash `HISTFILE` / `histappend` project-shell management;
- tracked Starship configuration if unused elsewhere;
- rich-terminfo probing added specifically for Comint/Starship;
- tests that assert implementation-specific Comint/Bash behavior rather than the user-visible project-shell contract.

Do not remove general `shell-mode` support if other workflows still use it. The cleanup is scoped to the project-shell architecture.

## Failure handling

If Eat is unavailable or fails to initialize, ordinary Eshell should remain usable. Terminal-native programs may then fail with a clear user-facing explanation rather than silently producing a corrupted interface.

Package/bootstrap behavior should make Eat available through the existing package-management conventions, but project-shell creation should not perform network installation or expensive package setup synchronously.

On native Windows, Eat + Codex must be treated as an empirical compatibility requirement rather than assumed from Linux behavior. If native Windows terminal support has a platform limitation, surface it explicitly during implementation review rather than adding an unrelated fallback shell stack without discussion.

## Testing

Implementation follows TDD. Required regression coverage should be behavioral rather than testing Eshell/Eat internals.

### Platform-neutral tests

- project shell resolves the same semantic project root as other P3 project-aware processes;
- one primary shell is reused per project;
- an explicit extra session creates a distinct shell;
- toggle/other-window/switch/rename/kill behavior remains correct;
- the project shell is Eshell-based, not `shell-mode`/Comint-based;
- startup does not inject Bash bootstrap commands and produces no P3-generated duplicate prompts;
- prompt/history setup is Eshell-native;
- absence of Eat leaves ordinary Eshell usable with a clear terminal-app limitation.

### Linux integration tests

- real project shell starts in the requested root;
- ordinary command execution works;
- Eat integration is active;
- a small terminal-control smoke program can use cursor/alternate-screen semantics without leaking raw control sequences into ordinary Eshell output;
- Codex-compatible terminal capability is present without requiring a separate manually opened terminal buffer.

### Native Windows integration tests

- Rtools/MSYS2 discovery continues to publish the external-tool environment used by Eshell commands;
- ordinary external Unix tools still resolve from the configured environment;
- project-root startup/reuse works on native Windows;
- Eat terminal integration starts successfully;
- terminal-control/alternate-screen smoke passes under native Windows;
- Codex is exercised when available, or a deterministic PTY/TUI fixture covers the same terminal contract when CI cannot install Codex.

The Windows test is a release gate for this architecture. Linux success alone is insufficient.

## Acceptance criteria

- One P3 project-shell command surface works on GNU/Linux and native Windows.
- The primary shell surface is Eshell and behaves like a normal Emacs buffer for routine work.
- Repeated invocation reuses one live primary shell per semantic project root.
- Explicit additional project shells remain supported.
- Org-associated project context still routes shells to the associated project rather than the note directory.
- Startup shows one prompt and no P3 Bash-bootstrap commands or duplicate prompts.
- Normal history, completion, selection, search, scrolling, and kill-ring behavior work without a terminal copy mode.
- External commands inherit the expected project directory and platform environment.
- Windows retains Rtools/MSYS2 external-tool discovery without requiring the project shell itself to be Bash.
- Codex or an equivalent terminal-control acceptance fixture renders and interacts correctly through Eat from the project shell.
- Exiting a terminal-native program returns the user to normal Eshell editing in the same workflow.
- No separate user-facing terminal command is required merely to run a TUI.
- Obsolete Comint/Bash project-shell prompt, history, Starship, and terminfo machinery is removed when unused.
- Existing non-project-shell Comint consumers such as ESS remain unaffected.

## Non-goals

- Reimplement Bash semantics in Eshell.
- Make every Bash one-liner valid Eshell syntax.
- Replace ESS, Python REPLs, Magit, compilation mode, or other purpose-built Emacs workflows.
- Build a terminal multiplexer or persistent session database.
- Add WSL, PowerShell, Git Bash, or another parallel shell stack solely for symmetry.
- Preserve the current Starship implementation for its own sake.
- Make terminal emulation the default interaction mode for ordinary shell commands.

## Migration principle

This change should replace the failed architectural assumption rather than accumulate another compatibility layer. The final configuration should have one primary project-shell workflow: Eshell for ordinary interaction, with Eat supplying terminal semantics when needed.