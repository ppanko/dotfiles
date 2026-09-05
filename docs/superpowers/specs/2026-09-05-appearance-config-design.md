# Appearance Configuration Design

## Status

Approved design for the next Emacs modernization PR. This PR is intentionally allowed to simplify implementation rather than preserve package identity: it preserves the useful appearance and status information of the current configuration while replacing package-specific machinery that is not itself a user requirement.

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
2. Preserve the current platform font choices and the useful visual behavior of the existing setup.
3. Replace Doom-modeline with a small native custom mode line that remains modern-looking and functional.
4. Replace `all-the-icons` with one restrained `nerd-icons` stack across the mode line, Dashboard, and Dired.
5. Make file identity and major-mode identity explicitly icon-bearing when Nerd Font glyphs are available.
6. Keep icons supplemental: missing icon fonts must never break startup or hide information.
7. Prefer theme-derived faces and semantic faces over hard-coded palette values.
8. Keep the implementation small enough to understand directly rather than creating a home-grown modeline framework.
9. Preserve Emacs 29 compatibility while taking advantage of native Emacs 30 right alignment when available.
10. Leave encoding policy for a separate cleanup.

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
- introduce a general status-bar framework, segment registry, plugin API, caching layer, or package abstraction;
- automatically download fonts during ordinary startup.

A later theme-selection PR may compare `doom-palenight` with built-in themes after the new appearance layer is stable.

## Ownership and orchestration

Add `lisp/p3-config-appearance.el` as the declarative owner of visual presentation. `config.org` should load it explicitly immediately after early platform setup and before `p3-config-base`.

The intended ordinary startup order becomes:

```text
early orchestration
  -> p3-config-appearance
  -> p3-config-base
  -> p3-config-editing
  -> remaining configuration modules
```

Loading appearance before base has one practical benefit: `nerd-icons` is available before Dashboard and Dired integrations in `p3-config-base.el` are configured. The appearance module's `nerd-icons` declaration should therefore be eager (`:demand t` or equivalent): the appearance module itself uses the package for the mode line, and base follows immediately with supported Dashboard/Dired integrations. Base must not call appearance-specific helper functions, so this remains top-level sequencing rather than a configuration-module dependency.

`p3-config-appearance.el` owns:

- maximized-frame startup;
- platform-specific default font family and size;
- cursor shape and blinking;
- menu/tool/scroll bars, tooltip, and fringe presentation;
- `doom-themes` / `doom-palenight` activation;
- the custom native mode line and its small formatting helpers;
- mode-line active/inactive styling;
- icon availability/fallback helpers used by the mode line;
- frame title;
- matching-paren presentation;
- line-number face styling.

`p3-config-base.el` continues to own Dashboard, Dired, and line-number *behavior*. It changes only where necessary to consume the new appearance stack:

- remove platform font, cursor, and maximized-frame settings that move to appearance;
- remove the per-buffer hard-coded line-number face mutation while retaining line-number activation;
- replace Dashboard's `all-the-icons` selection with `nerd-icons`;
- replace `all-the-icons-dired` with `nerd-icons-dired`;
- remove `all-the-icons` font-install and scale-factor machinery;
- absorb the nonvisual startup/scratch/bell settings currently stranded in the inline `Themes` section, because broad startup UI policy already belongs to base.

This keeps Dashboard and Dired package wiring with their existing owner rather than splitting their configuration across modules.

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
- no independent state/cache unless a demonstrated performance problem requires it.

### Information contract

The normal mode line has a left identity area and a right status area.

The **left area** contains:

1. buffer state, shown compactly when modified or read-only;
2. **file/buffer identity with an associated icon**;
3. concise project-relative file identity when visiting a project file, with a sensible buffer-name fallback otherwise;
4. **major-mode identity with an associated icon and short textual mode name**;
5. `mode-line-process` information when a major mode exposes meaningful subprocess state.

The **right area** contains:

1. Git/VC identity when present, with a Git/branch glyph and branch/status text;
2. Flycheck diagnostic state when available, using compact success/warning/error glyphs and counts rather than reproducing Flycheck's default prose;
3. encoding and EOL information in concise text form;
4. line and column position.

The exact glyphs and separators are implementation details, but the visual style should be flat, sparse, and consistent rather than icon-heavy.

### File and mode icons

File and major-mode identity are primary icon use cases, not optional decoration.

When Nerd Font rendering is available:

- file identity uses the appropriate `nerd-icons` file icon for the visited file where possible;
- non-file buffers use a stable generic/buffer fallback;
- major-mode identity uses the corresponding `nerd-icons` mode icon where available.

The file name and mode name remain textual, so the icon never becomes the only carrier of identity.

### Narrow-window behavior

The mode line must degrade deliberately rather than simply overflow. Keep the implementation simple:

- preserve the actual filename before parent-path detail when shortening project-relative identity;
- preserve line/column position;
- allow lower-priority detail such as encoding/EOL text or extended diagnostic/process text to disappear or shorten in narrow windows;
- use only a small number of direct width checks rather than a generic priority/segment engine.

This is a readability rule, not a request for a dynamic layout framework.

### Git and diagnostics

Git information should use built-in VC state (`vc-mode`) rather than introducing a Git-status dependency. Appearance code may format that state, but it must not own Git behavior.

Diagnostic information may inspect Flycheck state when Flycheck is loaded and active, but `p3-config-appearance.el` must not require `p3-config-editing` or otherwise create a configuration-module dependency. If Flycheck is absent or disabled, the diagnostic segment simply disappears.

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
- Git/VC;
- diagnostics;
- optionally read-only/modified state when a simple Unicode symbol is not clearer.

Avoid decorative icons for encoding, line/column, separators, or every minor status value.

### Font availability

Do not automatically run `nerd-icons-install-fonts` during startup.

The preferred icon font is the normal `nerd-icons` `Symbols Nerd Font Mono` family. Before emitting private-use Nerd Font glyphs, the mode-line formatter should verify that:

- Emacs is displaying graphically; and
- the configured Nerd Font family is actually available.

If either condition is false, render a Unicode/text fallback. No startup error, tofu glyph, blocking prompt, or required package-specific setup state is acceptable.

Installing the Nerd Font remains an explicit one-time user action through the package's normal command.

The chosen Unicode fallbacks should be common, narrow glyphs rather than emoji whose width/color varies substantially across platforms.

## Dashboard and Dired icon migration

Dashboard already supports `dashboard-icon-type 'nerd-icons`; use that supported path rather than compatibility wrappers.

Dired should use `nerd-icons-dired` through its standard `dired-mode` hook.

Remove active `all-the-icons` and `all-the-icons-dired` declarations, declarations/functions used only to install their font collection, and the obsolete commented Telephone Line reference if it is part of the same dead appearance block.

Dashboard and Dired may use their package-provided Nerd Font behavior directly; the stricter Unicode fallback contract is required for the P3 custom mode line, which P3 controls. A missing icon font must still not prevent Dashboard or Dired from opening normally.

## Unicode font handling

Remove the broad `unicode-fonts` package setup from `config.org`.

The system's normal font fallback remains responsible for ordinary Unicode text, while `nerd-icons` is responsible only for its icon glyphs. The mode-line Unicode fallback set must therefore use widely available symbols.

If interactive verification exposes a real missing-glyph problem for normal document text, fix that later with a targeted fontset rule for the demonstrated character range rather than restoring a broad package preemptively.

After this move, the remaining `Encoding & fonts` section should become an encoding-focused section containing only the existing coding-system policy and `.Rmd` CRLF rule until the dedicated encoding cleanup.

## Reload behavior

`p3-config-appearance.el` is loaded through `p3/config-load-module`, so `C-c r` re-evaluates its exact source.

Reload must:

- redefine the small mode-line formatter functions;
- reset the default `mode-line-format` to the current source definition;
- reapply relevant face attributes after the theme is active;
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

- `config.org` explicitly loads `p3-config-appearance` before `p3-config-base`;
- the old inline Doom-modeline and appearance blocks are gone;
- platform fonts, cursor presentation, theme, and mode-line ownership are in `p3-config-appearance.el`;
- `p3-config-base.el` no longer owns fonts/cursor/maximized-frame appearance;
- active repository configuration contains no `doom-modeline`, `all-the-icons`, `all-the-icons-dired`, or `unicode-fonts` package declaration;
- Dashboard selects `nerd-icons` and Dired uses `nerd-icons-dired`;
- encoding and `.Rmd` coding policy remain outside the appearance owner.

Tests should verify ownership and durable behavior, not exact whitespace or the final choice of individual glyph characters.

### Mode-line unit tests

Where practical without a graphical display, test formatter behavior for:

- project-relative file identity with a non-file fallback;
- major-mode text fallback;
- modified/read-only state;
- VC text presence/absence;
- diagnostics presence/absence when Flycheck state is simulated;
- concise encoding/EOL output;
- Emacs-30 native versus Emacs-29 fallback alignment selection;
- icon-disabled fallback paths that do not call Nerd Font rendering functions.

The tests should avoid depending on the icon font being installed on CI.

### Compilation and smoke loading

Add `p3-config-appearance.el` to warnings-as-errors byte compilation.

Add a smoke-load boundary test that suppresses package installation and stubs only the external theme/icon surfaces necessary to exercise the real appearance module in batch mode. The smoke test should prove that loading the module constructs a valid default mode line without a graphical display or Nerd Font.

Windows verification should at minimum cover byte compilation/source ownership of the new module and preservation of the existing Windows font family/size choice. Do not create a broad new Windows UI test suite that cannot verify graphical rendering.

### Full regression gate

Run the existing full ERT suite after focused tests pass. CI remains the executable gate for startup/reload behavior that can be exercised noninteractively.

## Manual graphical acceptance

Aesthetics cannot be established by batch CI. Before merge, perform one explicit graphical acceptance pass in normal Emacs.

Check at least:

1. an ordinary project file on a Git branch;
2. a modified file;
3. a read-only buffer;
4. a source buffer with Flycheck diagnostics;
5. a buffer with meaningful `mode-line-process` state;
6. a narrow window to confirm graceful truncation rather than unusable crowding;
7. Dashboard icons;
8. Dired icons;
9. active versus inactive window mode-line contrast;
10. `C-c r` to confirm appearance reload does not duplicate or corrupt state.

If `Symbols Nerd Font Mono` is absent, first confirm the Unicode/text fallback is clean, then install the font explicitly and confirm the icon-bearing graphical path.

Visual acceptance should focus on information hierarchy, spacing, truncation, and icon clarity. Pixel-perfect reproduction of Doom-modeline is explicitly not a requirement.

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
- UTF-8/process coding and `.Rmd` CRLF behavior exactly, outside this module.

The native mode line must preserve the useful information intent of the previous Doom-modeline configuration, not its package-specific implementation.

## Acceptance criteria

The PR is ready for final review when:

1. `p3-config-appearance.el` is the clear owner of visual presentation;
2. `config.org` has one concise appearance loader stanza rather than inline appearance implementation;
3. Doom-modeline and the old icon/font helper packages are no longer active dependencies;
4. the mode line shows icon-bearing file and mode identity, VC state, diagnostics when available, encoding/EOL, and position while remaining readable without Nerd Font glyphs;
5. no custom refresh loop, modeline framework, or config-module coupling has been introduced;
6. Emacs 29 alignment fallback and Emacs 30 native alignment are both represented in the implementation/test contract;
7. Dashboard and Dired use the same Nerd Font icon stack;
8. automated focused and full regression gates pass;
9. the graphical acceptance pass confirms the result is modern, restrained, readable, and functionally sufficient.

Do not merge without explicit approval.