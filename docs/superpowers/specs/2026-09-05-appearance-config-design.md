# Appearance Configuration Design

## Status

Approved design for the next Emacs modernization PR. This PR is intentionally allowed to simplify implementation rather than preserve package identity: it preserves useful appearance and status information while replacing package-specific machinery that is not itself a user requirement.

The target is a modern, restrained graphical Emacs UI built from native Emacs faces and mode-line facilities, `doom-palenight`, and a single `nerd-icons` icon stack.

## Problem

Appearance configuration is currently split across two architectural levels.

`lisp/p3-config-base.el` already owns some appearance state, including:

- maximized-frame startup;
- platform-specific default fonts;
- cursor shape;
- line-number activation plus a hard-coded current-line color;
- `all-the-icons` and `all-the-icons-dired` setup used by Dashboard and Dired.

Later in `config.org`, the remaining `Themes` and `Encoding & fonts` areas configure:

- frame chrome and cursor blinking;
- startup/scratch presentation and bell behavior;
- `doom-palenight`;
- `doom-modeline` through a large package-specific option list;
- hard-coded mode-line and border colors;
- frame title and matching-paren highlighting;
- `unicode-fonts`;
- encoding and the `.Rmd` CRLF rule.

This split obscures ownership and leaves the visual result dependent on several overlapping packages and hard-coded face colors. The current Doom-modeline configuration also disables a substantial portion of Doom-modeline's feature surface, so the dependency is larger than the functionality actually used.

## Goals

1. Give visual appearance one clear configuration owner.
2. Preserve the current platform font choices and useful visual behavior.
3. Replace Doom-modeline with a small native custom mode line that remains modern-looking and functional.
4. Replace `all-the-icons` with one restrained `nerd-icons` stack across the mode line, Dashboard, and Dired.
5. Make file identity and major-mode identity explicitly icon-bearing when Nerd Font glyphs are available.
6. Keep icons supplemental: missing icon fonts must never break startup or hide information.
7. Prefer theme-derived and semantic faces over hard-coded palette values.
8. Keep the implementation small enough to understand directly rather than creating a home-grown modeline framework.
9. Keep mode-line redisplay cheap and safe for local and remote buffers.
10. Preserve Emacs 29 compatibility while taking advantage of native Emacs 30 right alignment when available.
11. Leave encoding policy for a separate cleanup.

## Non-goals

This PR does not:

- replace `doom-palenight` or evaluate alternative themes;
- redesign Dashboard content or Dired behavior;
- change project identity or project navigation;
- change Flycheck policy or diagnostic thresholds;
- change Git behavior;
- change completion, ESS, Python, Org, terminal, GPTel, LaTeX, SQL, Poly-R, TRAMP, or workgroups;
- change UTF-8/process coding policy;
- change the `.Rmd` CRLF rule;
- introduce a general status-bar framework, segment registry, plugin API, generalized caching layer, or package abstraction;
- automatically download fonts during ordinary startup;
- reimplement Doom-modeline environment/version probing by launching interpreters or subprocesses.

A later theme-selection PR may compare `doom-palenight` with built-in themes after the new appearance layer is stable.

## Ownership and orchestration

Add `lisp/p3-config-appearance.el` as the declarative owner of visual presentation. `config.org` should load it explicitly as an ordinary configuration module adjacent to the existing base layer.

Correctness must **not** depend on whether `p3-config-base` has already loaded. This preserves the architecture rule that module order must not substitute for an undocumented configuration-module dependency.

A suitable top-level order is:

```text
early orchestration
  -> p3-config-base
  -> p3-config-appearance
  -> p3-config-editing
  -> remaining configuration modules
```

The order is chosen for readability, not because Base consumes Appearance state.

`p3-config-appearance.el` owns:

- maximized-frame startup;
- platform-specific default font family and size;
- cursor shape and blinking;
- menu/tool/scroll bars, tooltip, and fringe presentation;
- `doom-themes` / `doom-palenight` activation;
- the custom native mode line and its small formatting helpers;
- mode-line active/inactive styling;
- icon availability/fallback helpers;
- `nerd-icons`;
- Dashboard icon presentation;
- `nerd-icons-dired` and its Dired icon hook;
- frame title;
- matching-paren presentation;
- line-number face styling.

`p3-config-base.el` continues to own Dashboard, Dired, and line-number **behavior**. It changes only to remove visual ownership that moves to Appearance:

- remove platform font, cursor, and maximized-frame settings;
- remove the per-buffer hard-coded line-number face mutation while retaining line-number activation;
- remove `all-the-icons`, `all-the-icons-dired`, their font-install logic, and their scale-factor machinery;
- retain Dashboard content/startup behavior without choosing its icon implementation;
- retain Dired behavior without choosing its icon implementation;
- absorb the nonvisual startup/scratch/bell settings currently stranded in the inline `Themes` section, because broad startup UI policy already belongs to Base.

Appearance configures Dashboard visually through the Dashboard package load boundary, so it works whether Dashboard loaded before or after Appearance. Dired icon presentation is similarly owned directly by Appearance through `nerd-icons-dired`, not by Base.

No configuration module should call helper functions defined by another configuration module.

## Theme and faces

Keep `doom-themes` and `doom-palenight` unchanged as the theme choice for this PR. The mode-line rewrite and theme replacement should not happen simultaneously; otherwise visual regressions are harder to attribute.

Remove hard-coded palette overrides such as the current literal mode-line background, vertical-border color, and gold current-line-number foreground. Prefer:

- the theme's `mode-line` and `mode-line-inactive` backgrounds;
- inherited semantic faces such as `error`, `warning`, `success`, `shadow`, and `mode-line-buffer-id`;
- small structural adjustments such as removing boxes, setting weight, or adjusting height without fixing specific palette colors.

The active mode line should be visually distinct and the inactive mode line should recede, but both should remain theme-coherent.

## Native mode line

### Design principle

The new mode line is custom, but native. It uses `mode-line-format`, faces, and a small number of dedicated formatter functions in `p3-config-appearance.el`. It must not grow into a modeline package of its own.

A useful complexity bound is:

- one `mode-line-format` definition;
- a handful of small segment-formatting functions;
- no segment registry;
- no extension protocol;
- no custom refresh timer;
- no generalized cache or independent modeline state machine.

A small buffer-local cache of derived presentation values is permitted only where it prevents expensive redisplay work. Such cached values must remain narrowly scoped to appearance and refresh through ordinary buffer/file/mode events rather than timers.

### Information contract

The normal mode line has a left identity area and a right status area.

The **left area** contains:

1. buffer state, shown compactly when modified or read-only;
2. remote-host identity for remote buffers, using host text plus a restrained remote glyph when icons are available;
3. **file/buffer identity with an associated icon**;
4. concise project-relative file identity for local project files, with a sensible buffer-name fallback otherwise;
5. **major-mode identity with an associated icon and short textual mode name**;
6. `mode-line-process` information when a major mode exposes meaningful subprocess state.

The **right area** contains:

1. Git/VC identity when present, with a Git/branch glyph and bounded branch/status text;
2. Flycheck state when available;
3. encoding and EOL information in concise text form;
4. line and column position.

The existing Doom-modeline environment/version feature is deliberately **not** part of the replacement contract. Recreating it would require package-specific environment knowledge or process/version probing that is disproportionate to its value. If a mode already exposes useful environment text cheaply through ordinary mode-line state, that state may remain visible through `mode-line-process`; Appearance must not add new interpreter/version detection.

The existing VCS length constraint is preserved in spirit: branch/status text should remain bounded rather than allowing arbitrarily long repository metadata to dominate the mode line. A 12-character branch-name ceiling is the default target unless implementation evidence shows a slightly different fixed bound reads materially better.

The exact glyphs and separators are implementation details, but the visual style should be flat, sparse, and consistent rather than icon-heavy.

### File, remote, and mode identity

File and major-mode identity are primary icon use cases, not optional decoration.

When Nerd Font rendering is available:

- file identity uses the appropriate `nerd-icons` file icon for the visited file where possible;
- non-file buffers use a stable generic/buffer fallback;
- major-mode identity uses the corresponding `nerd-icons` mode icon where available;
- remote buffers use a restrained remote/host glyph plus host text.

The file name, remote host, and mode name remain textual, so the icon never becomes the only carrier of identity.

Remote identity must be derived from already-available TRAMP path information such as `file-remote-p`; rendering it must not initiate a remote connection or remote filesystem access.

### Narrow-window behavior

The mode line must degrade deliberately rather than simply overflow. Keep the implementation simple:

- preserve the actual filename before parent-path detail when shortening local project-relative identity;
- preserve remote host identity for remote files;
- preserve line/column position;
- allow lower-priority detail such as encoding/EOL text or extended diagnostic/process text to disappear or shorten in narrow windows;
- use only a small number of direct width checks rather than a generic priority/segment engine.

This is a readability rule, not a request for a dynamic layout framework.

### Redisplay performance contract

Mode-line formatter code runs during redisplay and must therefore remain cheap.

A formatter must **not** synchronously perform any of the following on each redisplay:

- project discovery or directory walking;
- filesystem existence/stat calls solely for presentation;
- remote filesystem access or TRAMP connection work;
- package loading via `require`/autoload-triggering lookups;
- Git/VC refresh operations;
- interpreter or subprocess execution;
- font installation or package setup;
- repeated expensive icon/package discovery.

Prefer already-available Emacs state such as `buffer-file-name`, `default-directory`, `major-mode`, `mode-name`, `vc-mode`, `mode-line-process`, Flycheck status variables, and coding-system variables.

For local project-relative identity, do not call `project-current` from the redisplay formatter. If project-relative naming requires project discovery, derive it outside redisplay and store only the resulting presentation context in a small buffer-local variable refreshed at appropriate file/buffer/project events. Remote buffers must skip project discovery entirely unless project state was already established elsewhere without remote I/O.

`nerd-icons` itself should be loaded eagerly by Appearance so redisplay never triggers package loading. Icon-font availability may be computed once per appearance reload or otherwise memoized cheaply; it must not run an expensive font scan for every segment on every redisplay.

The graphical acceptance pass should include a subjective latency check in both local and remote/TRAMP buffers. Any noticeable typing, scrolling, or redisplay lag is a blocker even if automated tests pass.

### Git and diagnostics

Git information should use built-in VC presentation state such as `vc-mode` rather than introducing a Git-status dependency or asking VC to refresh during redisplay. Appearance may format existing VC state, but it must not own Git behavior.

Diagnostic information may inspect Flycheck state when Flycheck is already loaded and active, but `p3-config-appearance.el` must not require `p3-config-editing` or force-load Flycheck during redisplay.

The Flycheck segment should interpret `flycheck-last-status-change` deliberately:

- `running`: compact progress/checking indicator, without stale counts presented as current;
- `finished`: show clean/success when there are no current errors, otherwise show compact error/warning/info counts;
- `errored`: error/failure indicator;
- `suspicious`: warning indicator;
- `interrupted`: neutral/interrupted indicator or no segment if that is visually clearer;
- `no-checker` / `not-checked`: no diagnostic segment;
- Flycheck absent or disabled: no diagnostic segment.

Diagnostic coloring should inherit semantic faces rather than hard-code theme colors.

### Emacs 29 and 30 alignment

On Emacs 30 and newer, place the right area after `mode-line-format-right-align`, using the native right-alignment facility.

Emacs 29 remains supported. When the native marker is unavailable, use one small compatibility formatter based on the conventional mode-line `display`/`space :align-to` mechanism. The fallback exists only for alignment; it must not become a parallel modeline implementation.

Tests should cover selection of the native versus fallback alignment path independently of whichever Emacs version CI happens to run.

## Icon strategy

Use **Unicode + `nerd-icons`**.

`nerd-icons` becomes the only icon framework in active configuration. The normal graphical path uses Nerd Font glyphs where they add useful recognition; ordinary Unicode or text is used for simple state and as fallback.

The mode line should normally use only a few icon categories:

- file type;
- major mode;
- remote/host identity;
- Git/VC;
- diagnostics;
- optionally read-only/modified state when a simple Unicode symbol is not clearer.

Avoid decorative icons for encoding, line/column, separators, or every minor status value.

### Font availability

Do not automatically run `nerd-icons-install-fonts` during startup.

The preferred icon font is the normal `nerd-icons` `Symbols Nerd Font Mono` family. Before emitting private-use Nerd Font glyphs, Appearance should determine that:

- Emacs is displaying graphically; and
- the configured Nerd Font family is actually available.

If either condition is false, render Unicode/text fallbacks in the custom mode line and keep package-owned icon integrations disabled. No startup error, tofu glyph, blocking prompt, or required package-specific setup state is acceptable.

Installing the Nerd Font remains an explicit one-time user action through the package's normal command. After installation, `C-c r` should be sufficient to re-evaluate icon availability and enable the icon-bearing path.

The chosen Unicode fallbacks should be common, narrow glyphs rather than emoji whose width/color varies substantially across platforms.

## Dashboard and Dired icon migration

Dashboard and Dired icon presentation belongs to Appearance, not Base.

For Dashboard:

- use the package's supported `dashboard-icon-type 'nerd-icons` path when the Nerd Font is available;
- apply the setting through the Dashboard load boundary so correctness is independent of whether Dashboard loaded before or after Appearance;
- when the Nerd Font is unavailable, leave Dashboard in a text-safe/non-icon presentation rather than selecting an icon backend that will render tofu.

For Dired:

- use `nerd-icons-dired` through its normal `dired-mode` integration when the Nerd Font is available;
- when unavailable, do not enable the Nerd Font Dired presentation hook;
- on `C-c r`, reconcile the hook idempotently so installing the font and reloading enables icons without accumulating duplicate hook entries.

Remove active `all-the-icons` and `all-the-icons-dired` declarations, declarations/functions used only to install their font collection, and the obsolete commented Telephone Line reference if it is part of the same dead appearance block.

Missing icon fonts must never prevent Dashboard or Dired from opening normally.

## Unicode font handling

Remove the broad `unicode-fonts` package setup from `config.org`.

The system's normal font fallback remains responsible for ordinary Unicode text, while `nerd-icons` is responsible only for its icon glyphs. The mode-line Unicode fallback set must therefore use widely available symbols.

The graphical acceptance pass must include a normal text buffer containing representative non-ASCII punctuation and symbols, for example `—`, `→`, `✓`, `λ`, and `∑`, and confirm that ordinary font fallback remains readable on the supported platform. This check is separate from Nerd Font icon rendering.

If interactive verification exposes a real missing-glyph problem for normal document text, fix that later with a targeted fontset rule for the demonstrated character range rather than restoring a broad package preemptively.

After this move, the remaining `Encoding & fonts` section should become an encoding-focused section containing only the existing coding-system policy and `.Rmd` CRLF rule until the dedicated encoding cleanup.

## Reload behavior

`p3-config-appearance.el` is loaded through `p3/config-load-module`, so `C-c r` re-evaluates its exact source.

Reload must:

- redefine the small mode-line formatter functions;
- reset the default `mode-line-format` to the current source definition;
- reapply relevant face attributes after the theme is active;
- recompute icon-font availability;
- reconcile Dashboard/Dired icon integration with current font availability;
- remain idempotent: repeated reloads must not accumulate hooks, advice, timers, or duplicate list entries.

Using `setq-default` for the P3 default mode line should preserve specialized buffers that deliberately install their own buffer-local `mode-line-format`.

## Package removals and additions

Remove active configuration for:

- `doom-modeline`;
- `all-the-icons`;
- `all-the-icons-dired`;
- `unicode-fonts`.

Add/use:

- `nerd-icons`;
- `nerd-icons-dired`.

Retain:

- `doom-themes` with `doom-palenight`.

No additional modeline, icon-completion, minibuffer-icon, or styling package should be introduced in this PR.

## Testing

### Structural ownership tests

Add focused tests asserting that:

- `config.org` explicitly loads `p3-config-appearance` as an ordinary module adjacent to Base;
- no correctness assertion depends on Appearance loading before Base;
- the old inline Doom-modeline and appearance blocks are gone;
- platform fonts, cursor presentation, theme, mode-line ownership, and visual icon integrations are in `p3-config-appearance.el`;
- `p3-config-base.el` no longer owns fonts/cursor/maximized-frame or icon-backend presentation;
- active repository configuration contains no `doom-modeline`, `all-the-icons`, `all-the-icons-dired`, or `unicode-fonts` package declaration;
- Dashboard's Nerd Icon presentation and Dired's `nerd-icons-dired` integration are owned by Appearance;
- encoding and `.Rmd` coding policy remain outside the appearance owner;
- Appearance does not require or call another `p3-config-*` module.

Tests should verify ownership and durable behavior, not exact whitespace or the final choice of individual glyph characters.

### Mode-line unit tests

Where practical without a graphical display, test formatter behavior for:

- project-relative local file identity with a non-file fallback;
- remote path/host identity without initiating remote I/O;
- major-mode text fallback;
- modified/read-only state;
- bounded VC text presence/absence;
- deliberate omission of environment/version probing;
- Flycheck `running`, `finished` clean/error, `errored`, `suspicious`, `interrupted`, `no-checker`, and absent/disabled states;
- concise encoding/EOL output;
- Emacs-30 native versus Emacs-29 fallback alignment selection;
- icon-disabled fallback paths that do not call Nerd Font rendering functions;
- formatter paths that consume pre-derived project context rather than invoking project discovery during redisplay.

The tests should avoid depending on the icon font being installed on CI.

### Performance-oriented regression tests

Where practical, instrument or stub expensive operations and assert that rendering the mode-line formatter does not invoke:

- `project-current`;
- subprocess execution;
- package loading;
- explicit VC refresh;
- remote filesystem access.

These tests are guards against architectural regressions, not microbenchmarks.

### Compilation and smoke loading

Add `p3-config-appearance.el` to warnings-as-errors byte compilation.

Add a smoke-load boundary test that suppresses package installation and stubs only the external theme/icon surfaces necessary to exercise the real appearance module in batch mode. The smoke test should prove that loading the module constructs a valid default mode line without a graphical display or Nerd Font.

Windows verification should at minimum cover byte compilation/source ownership of the new module and preservation of the existing Windows font family/size choice. Do not create a broad new Windows UI test suite that cannot verify graphical rendering.

### Full regression gate

Run the existing full ERT suite after focused tests pass. CI remains the executable gate for startup/reload behavior that can be exercised noninteractively.

## Manual graphical acceptance

Aesthetics cannot be established by batch CI. Before merge, perform one explicit graphical acceptance pass in normal Emacs.

Check at least:

1. an ordinary local project file on a Git branch;
2. a modified file;
3. a read-only buffer;
4. a source buffer while Flycheck is running and after it finishes with diagnostics;
5. a buffer with meaningful `mode-line-process` state;
6. a narrow window to confirm graceful truncation rather than unusable crowding;
7. a remote/TRAMP buffer, when an endpoint is available, confirming visible host identity and no noticeable redisplay lag;
8. Dashboard icons;
9. Dired icons;
10. active versus inactive window mode-line contrast;
11. a normal text buffer containing representative Unicode punctuation/symbols such as `— → ✓ λ ∑`;
12. `C-c r` to confirm appearance reload does not duplicate or corrupt state.

If `Symbols Nerd Font Mono` is absent, first confirm the Unicode/text fallback is clean and that Dashboard/Dired remain text-safe. Then install the font explicitly, run `C-c r`, and confirm the icon-bearing mode line, Dashboard, and Dired paths become active.

Visual acceptance should focus on information hierarchy, spacing, truncation, icon clarity, and responsiveness. Pixel-perfect reproduction of Doom-modeline is explicitly not a requirement.

## Behavioral invariants

This PR should preserve:

- `doom-palenight` as the active theme;
- the current Windows `Consolas` 125 default font choice;
- the current GNU/Linux `Inconsolata` 140 default font choice;
- maximized-frame startup;
- bar cursor semantics;
- suppressed toolbar/scrollbar/menu-style chrome currently configured;
- concise frame title based on the current buffer;
- matching-paren highlighting;
- existing line-number activation policy;
- Dashboard content and startup behavior apart from icon implementation;
- Dired behavior apart from icon implementation;
- remote-buffer host identity in the mode line;
- bounded VCS/branch presentation;
- UTF-8/process coding and `.Rmd` CRLF behavior exactly, outside this module.

The native mode line must preserve the useful information intent of the previous Doom-modeline configuration, not its package-specific implementation. Environment/version probing is the explicit exception: it is intentionally dropped unless a major mode already exposes equivalent information cheaply through ordinary mode-line state.

## Acceptance criteria

The PR is ready for final review when:

1. `p3-config-appearance.el` is the clear owner of visual presentation;
2. `config.org` has one concise appearance loader stanza rather than inline appearance implementation;
3. Base does not depend on Appearance or own the selected icon backend;
4. Doom-modeline and the old icon/font helper packages are no longer active dependencies;
5. the mode line shows icon-bearing file and mode identity, remote host when applicable, bounded VC state, Flycheck state, encoding/EOL, and position while remaining readable without Nerd Font glyphs;
6. environment/version probing is intentionally absent unless supplied cheaply by existing major-mode state;
7. redisplay formatters do not perform project discovery, remote/file I/O, package loading, VC refresh, or subprocess execution;
8. no custom refresh loop, modeline framework, or config-module coupling has been introduced;
9. Emacs 29 alignment fallback and Emacs 30 native alignment are both represented in the implementation/test contract;
10. Dashboard and Dired use the same Nerd Font icon stack only when its font is available and remain text-safe otherwise;
11. automated focused and full regression gates pass;
12. the graphical acceptance pass confirms the result is modern, restrained, readable, responsive, and functionally sufficient.

Do not merge without explicit approval.
