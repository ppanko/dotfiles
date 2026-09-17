# Eshell + Eat Windows acceptance amendment

Date: 2026-09-17

This amendment supersedes the native-Windows TUI/PTY requirements in `2026-09-16-eshell-eat-project-shell-design.md` and the corresponding stop conditions in the implementation plan.

## Revised constraint

Codex and other terminal-native TUIs on native Windows are **not** a project-shell requirement.

The project shell still has one user-facing Eshell workflow on GNU/Linux and native Windows. The acceptance contract is now platform-specific only at the terminal-emulation boundary:

- **GNU/Linux:** Eat must provide a real interactive terminal contract for terminal-native applications: TTY/PTY semantics, raw input, terminal dimensions, escape-sequence rendering, clean exit, and return to the same managed Eshell buffer. Codex remains the manual acceptance case.
- **Native Windows:** the managed project Eshell must start at the correct semantic project root, preserve normal Emacs editing/history/completion behavior, reuse project sessions correctly, execute ordinary external CLI commands through the configured Windows tool environment, and return cleanly after child processes. A child reporting `isatty = 0:0` is acceptable. Codex/full-screen TUI behavior is outside scope.

## Consequences

The native-Windows feasibility result observed in CI—Eat executes and interprets the fixture but the child receives no real TTY—is no longer a stop condition. Production migration may proceed as long as the ordinary Windows Eshell/external-command contract remains green.

No second Windows-specific shell surface, WSL requirement, or terminal backend is introduced to compensate for the missing PTY. The existing `p3/windows-configure-shell` behavior remains available for ordinary `M-x shell`; `p3/project-shell` itself remains Eshell-backed on both platforms.

Final CI should therefore require the full terminal fixture contract on GNU/Linux and the non-PTY subset on native Windows.