# Appearance Configuration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current split appearance stack with one focused appearance owner, a lean Unicode + `nerd-icons` visual layer, and a modern native Emacs mode line without introducing config-module coupling or redisplay latency.

**Architecture:** `config.org` remains the top-level composition map. `lisp/p3-config-appearance.el` becomes the sole owner of visual presentation, including theme, fonts, frame chrome, mode-line formatting, icon availability, and Dashboard/Dired icon presentation; `lisp/p3-config-base.el` retains only Dashboard/Dired/line-number behavior. The custom mode line consumes already-available buffer/VC/Flycheck state and pre-derived local project context so redisplay never performs project discovery, remote I/O, package loading, VC refresh, or subprocess execution.

**Tech Stack:** Emacs Lisp; `use-package`; built-in `mode-line-format`, `project.el`, VC and TRAMP path parsing; Flycheck state variables; `doom-themes`; `nerd-icons`; `nerd-icons-dired`; ERT; GitHub Actions on Ubuntu and Windows.

**Spec:** `docs/superpowers/specs/2026-09-05-appearance-config-design.md`

## Global Constraints

- Keep `doom-palenight` as the active theme in this PR.
- Keep Windows default font `Consolas` at height `125` and GNU/Linux default font `Inconsolata` at height `140`.
- Preserve maximized startup, bar cursor semantics, current line-number activation policy, frame-title intent, matching-paren highlighting, Dashboard content, Dired behavior, UTF-8/process coding, and the `.Rmd` CRLF rule.
- Replace `doom-modeline`, `all-the-icons`, `all-the-icons-dired`, and `unicode-fonts`; add only `nerd-icons` and `nerd-icons-dired` for this visual cleanup.
- File identity and major-mode identity must retain textual labels and use associated Nerd Font icons when available.
- Remote buffers must show host identity without initiating remote access.
- Do not recreate Doom-modeline environment/version probing; preserve environment text only when an existing mode already exposes it cheaply through `mode-line-process`.
- Keep VCS text bounded; target a 12-character rendered VC payload before ellipsis.
- Emacs 30 uses `mode-line-format-right-align`; Emacs 29 uses one narrow `space :align-to` fallback.
- No configuration module may require or call another `p3-config-*` module.
- No custom mode-line refresh timer, segment registry, extension protocol, generalized cache, or status-bar framework.
- Redisplay formatters must not call `project-current`, perform file/remote I/O, refresh VC, load packages, run subprocesses, or repeatedly scan fonts.
- Nerd Font absence must leave the mode line, Dashboard, and Dired text-safe; startup must not install fonts automatically.
- Do not merge without explicit approval.

---

### Task 1: Pin the appearance ownership boundary with failing tests

**Files:**
- Create: `test/p3-config-appearance-test.el`
- Modify: `test/p3-config-test.el`

**Interfaces:**
- Consumes: repository source files through the existing source-reading test pattern in `test/p3-config-test.el`.
- Produces: structural acceptance tests for `p3-config-appearance.el`, the fifteenth explicit config-module loader, removal of old appearance package ownership, and absence of cross-config-module coupling.

- [ ] **Step 1: Add the focused structural test file**

Create `test/p3-config-appearance-test.el` with helpers mirroring the existing ownership tests and these tests:

```elisp
;;; p3-config-appearance-test.el --- Appearance ownership tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'subr-x)

(defconst p3-config-appearance-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(defun p3-config-appearance-test--contents (relative)
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name relative p3-config-appearance-test--root))
    (buffer-string)))

(ert-deftest p3-config-appearance-has-one-top-level-owner ()
  (let ((config (p3-config-appearance-test--contents "config.org")))
    (should (= 1
               (let ((start 0) (count 0)
                     (needle "(p3/config-load-module 'p3-config-appearance)"))
                 (while (string-match (regexp-quote needle) config start)
                   (setq count (1+ count)
                         start (match-end 0)))
                 count)))))

(ert-deftest p3-config-appearance-owns-visual-stack ()
  (let ((appearance
         (p3-config-appearance-test--contents "lisp/p3-config-appearance.el"))
        (base (p3-config-appearance-test--contents "lisp/p3-config-base.el"))
        (config (p3-config-appearance-test--contents "config.org")))
    (dolist (needle '("(use-package doom-themes"
                       "(use-package nerd-icons"
                       "nerd-icons-dired"
                       "doom-palenight"
                       "mode-line-format"))
      (should (string-match-p (regexp-quote needle) appearance)))
    (dolist (forbidden '("doom-modeline" "all-the-icons" "unicode-fonts"))
      (should-not (string-match-p forbidden appearance))
      (should-not (string-match-p forbidden base))
      (should-not (string-match-p forbidden config)))))

(ert-deftest p3-config-appearance-does-not-couple-config-modules ()
  (let ((appearance
         (p3-config-appearance-test--contents "lisp/p3-config-appearance.el")))
    (should-not
     (string-match-p
      "\\(?:require\\|p3/config-load-module\\).*p3-config-"
      appearance))))

(provide 'p3-config-appearance-test)
;;; p3-config-appearance-test.el ends here
```

Keep the tests structural: do not pin exact glyph characters or final whitespace.

- [ ] **Step 2: Update the global module-count/order regression**

In `test/p3-config-test.el`, change `p3-config-org-source-loads-fourteen-config-modules` to `p3-config-org-source-loads-fifteen-config-modules`, change the expected count from `14` to `15`, and add `p3-config-appearance` to the explicit module list.

In `p3-config-early-orchestration-order-is-explicit`, bind an `appearance` position and assert the readable top-level sequence:

```elisp
(base (p3-config-test--position
       "(p3/config-load-module 'p3-config-base)" contents))
(appearance (p3-config-test--position
             "(p3/config-load-module 'p3-config-appearance)" contents))
(editing (p3-config-test--position
          "(p3/config-load-module 'p3-config-editing)" contents))
```

with:

```elisp
(should (< rtools base))
(should (< base appearance))
(should (< appearance editing))
```

The order assertion is for the human-readable map only; the focused appearance test must separately prove there is no Base→Appearance or Appearance→Base function/module dependency.

- [ ] **Step 3: Run the focused RED tests**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-test.el \
  -l test/p3-config-appearance-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: FAIL because `lisp/p3-config-appearance.el` and its loader do not exist and the module count is still 14.

- [ ] **Step 4: Commit the RED tests**

```bash
git add test/p3-config-test.el test/p3-config-appearance-test.el
git commit -m "Add appearance ownership regressions"
```

---

### Task 2: Extract visual ownership and replace the icon stack

**Files:**
- Create: `lisp/p3-config-appearance.el`
- Modify: `lisp/p3-config-base.el`
- Modify: `config.org`
- Test: `test/p3-config-appearance-test.el`
- Test: `test/p3-config-test.el`

**Interfaces:**
- Consumes: `use-package`; built-in face/frame APIs; Dashboard package variables; `nerd-icons-font-family`; `nerd-icons-dired-mode`.
- Produces: `p3/appearance--icons-available`, `p3/appearance-refresh-icon-availability`, `p3/appearance-configure-dashboard-icons`, `p3/appearance-sync-dired-icons`, and the `p3-config-appearance` feature. Later mode-line tasks consume `p3/appearance--icons-available` but no Base function calls any Appearance helper.

- [ ] **Step 1: Extend RED tests for the migration details**

Add assertions to `test/p3-config-appearance-test.el` that:

```elisp
(should (string-match-p "dashboard-icon-type" appearance))
(should (string-match-p "nerd-icons-dired-mode" appearance))
(should-not (string-match-p "dashboard-icon-type" base))
(should-not (string-match-p "all-the-icons-dired-mode" base))
(should (string-match-p "initial-scratch-message" base))
(should (string-match-p "ring-bell-function" base))
```

Also assert that `config.org` still contains the UTF-8 coding policy and `.Rmd` coding-system rule while no longer containing `doom-modeline`, `unicode-fonts`, or the inline `Themes` implementation.

- [ ] **Step 2: Run the focused test and verify the new assertions fail**

Run the Task 1 focused command again.

Expected: FAIL on the still-inline appearance/icon ownership.

- [ ] **Step 3: Create the appearance owner with visual state and icon availability**

Start `lisp/p3-config-appearance.el` with the production declarations and visual state:

```elisp
;;; p3-config-appearance.el --- Visual presentation configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'subr-x)

(defvar dashboard-icon-type)
(defvar dashboard-set-heading-icons)
(defvar dashboard-set-file-icons)
(defvar nerd-icons-font-family)

(defvar p3/appearance--icons-available nil
  "Non-nil when the configured Nerd Font can be rendered graphically.")

(defun p3/appearance-refresh-icon-availability ()
  "Refresh whether Nerd Font icons are safe to render."
  (setq p3/appearance--icons-available
        (and (display-graphic-p)
             (find-font
              (font-spec :family
                         (or (and (boundp 'nerd-icons-font-family)
                                  nerd-icons-font-family)
                             "Symbols Nerd Font Mono"))))))

(add-to-list 'default-frame-alist '(fullscreen . maximized))

(when (eq system-type 'windows-nt)
  (set-face-attribute 'default nil :family "Consolas" :height 125))
(when (eq system-type 'gnu/linux)
  (set-face-attribute 'default nil :family "Inconsolata" :height 140))

(setq-default cursor-type 'bar)
(blink-cursor-mode 0)
(menu-bar-mode 0)
(when (fboundp 'scroll-bar-mode) (scroll-bar-mode 0))
(when (fboundp 'tool-bar-mode) (tool-bar-mode 0))
(when (fboundp 'tooltip-mode) (tooltip-mode 0))
(when (fboundp 'fringe-mode) (fringe-mode 1))

(use-package doom-themes
  :config
  (load-theme 'doom-palenight t))

(use-package nerd-icons
  :demand t
  :custom
  (nerd-icons-font-family "Symbols Nerd Font Mono")
  :config
  (p3/appearance-refresh-icon-availability))
```

Do not call `nerd-icons-install-fonts`.

Add theme-coherent structural face setup after the theme loads: remove boxes and adjust weight/height only; do not reintroduce literal palette colors.

- [ ] **Step 4: Put Dashboard/Dired visual integration in Appearance**

Add idempotent helpers:

```elisp
(defun p3/appearance-configure-dashboard-icons ()
  "Configure Dashboard icon presentation for current font availability."
  (setq dashboard-icon-type
        (and p3/appearance--icons-available 'nerd-icons)
        dashboard-set-heading-icons p3/appearance--icons-available
        dashboard-set-file-icons p3/appearance--icons-available))

(with-eval-after-load 'dashboard
  (p3/appearance-configure-dashboard-icons))

(use-package nerd-icons-dired
  :commands nerd-icons-dired-mode)

(defun p3/appearance-sync-dired-icons ()
  "Enable or disable the Dired icon hook according to font availability."
  (remove-hook 'dired-mode-hook #'nerd-icons-dired-mode)
  (when p3/appearance--icons-available
    (add-hook 'dired-mode-hook #'nerd-icons-dired-mode)))

(p3/appearance-sync-dired-icons)
```

After `nerd-icons` configuration, call both icon reconciliation helpers when their target package/function surfaces are available. `C-c r` must be able to recompute the font state and reconcile the hook without duplicate entries.

- [ ] **Step 5: Move the rest of visual presentation**

Move the current frame title, matching-paren setup, line-number face styling, theme, toolbar/scrollbar/menu/tooltip/fringe settings, and visual cursor behavior into Appearance.

Use theme/semantic faces rather than these old literal colors:

```text
#383E54
#323638
#FFD700
```

Move only line-number **face styling**; leave line-number activation in Base.

- [ ] **Step 6: Reduce Base to nonvisual behavior**

In `lisp/p3-config-base.el`:

- remove maximized-frame, platform font, and cursor settings;
- remove `all-the-icons-scale-factor`, `all-the-icons-install-fonts`, `all-the-icons`, and `all-the-icons-dired`;
- remove Dashboard's `dashboard-icon-type` assignment;
- remove `:after all-the-icons-dired` and the `all-the-icons-dired-mode` Dired hook;
- keep Dashboard content/setup and Dired behavior;
- keep `p3/set-line-numbers` but remove its hard-coded `set-face-foreground` call;
- add the nonvisual startup settings formerly in `Themes`:

```elisp
(setq inhibit-startup-message t
      initial-scratch-message nil
      initial-major-mode 'lisp-interaction-mode
      ring-bell-function #'ignore)
```

- [ ] **Step 7: Make `config.org` a concise appearance map**

Add immediately after Base:

```org
* Appearance

Theme, fonts, frame chrome, mode-line presentation, and icon presentation live
in =lisp/p3-config-appearance.el=.

#+BEGIN_SRC emacs-lisp
  (p3/config-load-module 'p3-config-appearance)
#+END_SRC
```

Remove the old inline `Themes` implementation, Doom-modeline block, commented Telephone Line block, and `unicode-fonts` declaration. Keep the existing UTF-8/process coding block and `.Rmd` CRLF rule under an encoding-focused heading.

- [ ] **Step 8: Run the focused ownership tests**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-test.el \
  -l test/p3-config-appearance-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS for the extraction/icon ownership tests. Mode-line behavior tests are added next.

- [ ] **Step 9: Commit the visual ownership migration**

```bash
git add config.org lisp/p3-config-base.el lisp/p3-config-appearance.el \
  test/p3-config-test.el test/p3-config-appearance-test.el
git commit -m "Extract appearance and icon configuration"
```

---

### Task 3: Build the cheap native mode-line identity layer

**Files:**
- Modify: `lisp/p3-config-appearance.el`
- Modify: `test/p3-config-appearance-test.el`

**Interfaces:**
- Consumes: `buffer-file-name`, `default-directory`, `major-mode`, `mode-name`, `mode-line-process`, `file-remote-p`, built-in `project-current` outside redisplay, and `nerd-icons-icon-for-file`, `nerd-icons-icon-for-buffer`, `nerd-icons-icon-for-mode` only when the cached icon flag is true.
- Produces: buffer-local `p3/appearance--project-root`, `p3/appearance--project-relative-file`; `p3/appearance-refresh-buffer-context`; `p3/appearance--remote-host`; `p3/appearance--buffer-state`; `p3/appearance--file-segment`; `p3/appearance--mode-segment`; `p3/appearance--left-segment`; `p3/appearance--native-right-align-p`; `p3/appearance--right-align-space`; and `p3/appearance--build-mode-line-format`.

- [ ] **Step 1: Add RED identity/alignment tests**

Add runtime tests to `test/p3-config-appearance-test.el`. Suppress package installation, provide lightweight Nerd Icons stubs before loading the real module, and test the real formatter functions.

Representative assertions:

```elisp
(ert-deftest p3-appearance-file-segment-keeps-text-without-icons ()
  (with-temp-buffer
    (setq buffer-file-name "/tmp/project/src/example.R"
          p3/appearance--icons-available nil
          p3/appearance--project-relative-file "src/example.R")
    (should (string-match-p "src/example\\.R"
                            (p3/appearance--file-segment)))))

(ert-deftest p3-appearance-remote-host-is-textual-and-local ()
  (with-temp-buffer
    (setq buffer-file-name "/ssh:example.org:/tmp/example.R")
    (should (equal "example.org" (p3/appearance--remote-host)))))

(ert-deftest p3-appearance-mode-segment-keeps-mode-name-without-icons ()
  (with-temp-buffer
    (emacs-lisp-mode)
    (let ((p3/appearance--icons-available nil))
      (should (string-match-p "Emacs-Lisp"
                              (p3/appearance--mode-segment))))))
```

Add alignment-path tests by temporarily overriding `p3/appearance--native-right-align-p` with `cl-letf`, not by depending on the CI Emacs version.

- [ ] **Step 2: Run the new tests and verify RED**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-appearance-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: FAIL because the formatter/cache functions are not defined yet.

- [ ] **Step 3: Implement buffer context derivation outside redisplay**

Add:

```elisp
(defvar-local p3/appearance--project-root nil)
(defvar-local p3/appearance--project-relative-file nil)

(defun p3/appearance-refresh-buffer-context ()
  "Refresh cheap presentation context for the current buffer."
  (setq p3/appearance--project-root nil
        p3/appearance--project-relative-file nil)
  (when (and buffer-file-name
             (not (file-remote-p buffer-file-name)))
    (when-let* ((project (project-current nil
                                         (file-name-directory buffer-file-name)))
                (root (project-root project)))
      (setq p3/appearance--project-root root
            p3/appearance--project-relative-file
            (file-relative-name buffer-file-name root)))))

(add-hook 'find-file-hook #'p3/appearance-refresh-buffer-context)
(add-hook 'after-change-major-mode-hook #'p3/appearance-refresh-buffer-context)
(when (boundp 'after-set-visited-file-name-hook)
  (add-hook 'after-set-visited-file-name-hook
            #'p3/appearance-refresh-buffer-context))
```

The formatter must read these buffer-local values; it must not call `project-current` itself.

- [ ] **Step 4: Implement textual/icon identity segments**

Implement the small segment functions. Use `condition-case` around Nerd Icons rendering so a package/icon lookup failure still yields text.

Rules:

- remote host from `(file-remote-p (or buffer-file-name default-directory) 'host)`;
- local wide-window file label uses cached project-relative path;
- narrow-window file label uses `file-name-nondirectory`;
- remote label uses host + filename, never project discovery;
- file icon uses `nerd-icons-icon-for-file` for files and `nerd-icons-icon-for-buffer` otherwise;
- mode icon uses `nerd-icons-icon-for-mode major-mode`;
- mode text comes from `(format-mode-line mode-name)`;
- modified/read-only state is always understandable as Unicode/text without the icon font;
- `mode-line-process` is rendered only from its existing mode-line construct.

Use `window-total-width` only for cheap presentation choices; do not create a generic priority engine.

- [ ] **Step 5: Implement Emacs 30 and Emacs 29 alignment**

Use:

```elisp
(defun p3/appearance--native-right-align-p ()
  (boundp 'mode-line-format-right-align))

(defun p3/appearance--right-align-space ()
  (let* ((right (p3/appearance--right-segment))
         (width (string-width right)))
    (propertize " " 'display
                `((space :align-to (- right ,(+ width 1)))))))
```

and make `p3/appearance--build-mode-line-format` insert the literal symbol `mode-line-format-right-align` on the native path, otherwise one `(:eval (p3/appearance--right-align-space))` fallback before the right segment.

Set the default with:

```elisp
(setq-default mode-line-format (p3/appearance--build-mode-line-format))
```

Do not overwrite buffers that already have a buffer-local `mode-line-format`.

- [ ] **Step 6: Run identity/alignment tests GREEN**

Run the focused appearance test command.

Expected: PASS.

- [ ] **Step 7: Commit the native identity layer**

```bash
git add lisp/p3-config-appearance.el test/p3-config-appearance-test.el
git commit -m "Add native appearance mode line"
```

---

### Task 4: Add VC, Flycheck, encoding, truncation, and redisplay guards

**Files:**
- Modify: `lisp/p3-config-appearance.el`
- Modify: `test/p3-config-appearance-test.el`

**Interfaces:**
- Consumes: existing `vc-mode`; `flycheck-last-status-change`, `flycheck-current-errors`, and `flycheck-count-errors` only when Flycheck is already loaded; `buffer-file-coding-system`; `window-total-width`.
- Produces: `p3/appearance--vc-segment`, `p3/appearance--flycheck-segment`, `p3/appearance--coding-segment`, `p3/appearance--position-segment`, and the completed `p3/appearance--right-segment`.

- [ ] **Step 1: Add RED status-state tests**

Add tests for:

- VC absent → no VC segment;
- VC string longer than the target bound → ellipsis and bounded width;
- Flycheck `running` → checking/progress indication without stale counts;
- Flycheck `finished` + no errors → success indication;
- Flycheck `finished` + simulated error/warning/info counts → compact counts;
- `errored` → failure indication;
- `suspicious` → warning indication;
- `interrupted` → neutral/short indication;
- `no-checker` and `not-checked` → no segment;
- Flycheck not loaded → no segment;
- encoding/EOL output for `utf-8-unix` and `utf-8-dos`;
- line/column segment always remains present.

Stub `flycheck-count-errors` only inside tests that simulate Flycheck; do not require Flycheck merely to render a buffer without it.

- [ ] **Step 2: Add RED performance regressions**

Use `cl-letf` to make expensive functions fail if called by the renderer:

```elisp
(cl-letf (((symbol-function 'project-current)
           (lambda (&rest _) (ert-fail "project-current during redisplay")))
          ((symbol-function 'process-file)
           (lambda (&rest _) (ert-fail "process-file during redisplay"))))
  (format-mode-line (default-value 'mode-line-format)))
```

For remote buffers, similarly guard `file-exists-p`, `file-attributes`, and `directory-files` while rendering. The formatter may call `file-remote-p` only to parse already-present remote path metadata.

Also assert that rendering with `p3/appearance--icons-available nil` never invokes a `nerd-icons-*` rendering function.

- [ ] **Step 3: Run the status/performance tests and verify RED**

Run the focused appearance test command.

Expected: FAIL because the status functions are not implemented.

- [ ] **Step 4: Implement bounded VC presentation**

Use only existing `vc-mode` state:

```elisp
(defun p3/appearance--vc-segment ()
  (when vc-mode
    (let* ((raw (string-trim (format-mode-line vc-mode)))
           (text (truncate-string-to-width raw 12 nil nil "…")))
      ;; Prefix with a Nerd Git/branch glyph only when cached icon availability is true.
      ...)))
```

Do not call `vc-refresh-state`, Git, or Magit from the formatter.

- [ ] **Step 5: Implement Flycheck state mapping**

Only inspect Flycheck when `(featurep 'flycheck)` and `flycheck-mode` is non-nil. Branch on `flycheck-last-status-change` exactly as specified:

```elisp
(pcase flycheck-last-status-change
  ('running ...)
  ('finished ...)
  ('errored ...)
  ('suspicious ...)
  ('interrupted ...)
  ((or 'no-checker 'not-checked) nil)
  (_ nil))
```

On `finished`, call `flycheck-count-errors` on the already-populated `flycheck-current-errors`; do not trigger a check. Render error/warning/info counts with inherited `error`, `warning`, and `success` faces.

- [ ] **Step 6: Implement coding/position and narrow-window policy**

Coding segment rules:

- use concise `UTF-8` text for UTF-8 coding;
- append `LF`, `CRLF`, or `CR` only when useful;
- do not add an icon for encoding.

Narrow-window initial thresholds:

- `< 120` columns: file identity drops parent/project path and keeps filename;
- `< 100` columns: omit encoding/EOL and `mode-line-process` detail;
- `< 80` columns: omit Flycheck counts beyond the single most important state indicator;
- line/column, actual filename, remote host, and major-mode identity remain.

These are initial deterministic rules; the graphical acceptance task may tune only these numeric thresholds/spacing if evidence shows the result is crowded.

- [ ] **Step 7: Run the focused suite GREEN**

Run the focused appearance test command.

Expected: PASS, including performance guards.

- [ ] **Step 8: Commit status and performance hardening**

```bash
git add lisp/p3-config-appearance.el test/p3-config-appearance-test.el
git commit -m "Complete appearance mode line status"
```

---

### Task 5: Make reload and CI coverage durable

**Files:**
- Modify: `test/p3-config-appearance-test.el`
- Modify: `.github/workflows/emacs-tests.yml`
- Modify: `.github/workflows/windows-platform-tests.yml`

**Interfaces:**
- Consumes: completed `p3-config-appearance.el` and focused appearance tests.
- Produces: idempotent reload regression; warnings-as-errors compilation on Ubuntu/Windows; non-graphical appearance smoke load; full ERT inclusion.

- [ ] **Step 1: Add a reload/idempotency regression**

Add a test that loads the real appearance module twice with icon availability forced false and verifies:

```elisp
(should (= 1 (cl-count #'p3/appearance-refresh-buffer-context
                       find-file-hook :test #'eq)))
(should (= 1 (cl-count #'p3/appearance-refresh-buffer-context
                       after-change-major-mode-hook :test #'eq)))
(should-not (memq #'nerd-icons-dired-mode dired-mode-hook))
(should (equal (default-value 'mode-line-format)
               (p3/appearance--build-mode-line-format)))
```

Then simulate icons becoming available, rerun the reconciliation helper twice, and assert `nerd-icons-dired-mode` occurs exactly once in `dired-mode-hook`.

- [ ] **Step 2: Run the reload test locally when Emacs is available**

Run:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-appearance-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS.

If the current execution environment has no Emacs executable, record that fact and use the PR Actions gates below as the executable evidence; do not substitute an unverified success claim.

- [ ] **Step 3: Extend Ubuntu compilation and smoke coverage**

In `.github/workflows/emacs-tests.yml`:

1. add `lisp/p3-config-appearance.el` to warnings-as-errors compilation;
2. add an Appearance smoke step before the full ERT suite;
3. add `-l test/p3-config-appearance-test.el` to the ERT command.

The smoke step should suppress package installation and provide minimal external surfaces:

```bash
emacs -Q --batch -L lisp \
  --eval '(require (quote use-package-ensure))' \
  --eval '(setq use-package-ensure-function (lambda (&rest _) t))' \
  --eval '(provide (quote doom-themes))' \
  --eval '(defvar nerd-icons-font-family "Symbols Nerd Font Mono")' \
  --eval '(provide (quote nerd-icons))' \
  --eval '(defun nerd-icons-icon-for-file (&rest _) "F")' \
  --eval '(defun nerd-icons-icon-for-buffer (&rest _) "B")' \
  --eval '(defun nerd-icons-icon-for-mode (&rest _) "M")' \
  -l lisp/p3-config-appearance.el \
  --eval '(unless (and (featurep (quote p3-config-appearance)) (listp (default-value (quote mode-line-format)))) (kill-emacs 1))'
```

If `load-theme` needs isolation in batch mode, stub `load-theme` in this smoke step rather than weakening production theme activation.

- [ ] **Step 4: Extend Windows path/compile/test coverage**

In `.github/workflows/windows-platform-tests.yml`:

- add `lisp/p3-config-appearance.el` and `test/p3-config-appearance-test.el` to `pull_request.paths`;
- add `lisp/p3-config-appearance.el` to strict Windows byte compilation;
- add `-l test/p3-config-appearance-test.el` to the Windows config-architecture ERT step.

Do not attempt graphical font rendering in Windows Actions.

- [ ] **Step 5: Run the complete local/static gates available in the execution environment**

Run the focused suite and, when Emacs exists, the full local ERT command matching `.github/workflows/emacs-tests.yml`.

Also inspect the diff for forbidden active dependencies:

```bash
git grep -n -E '\(use-package (doom-modeline|all-the-icons|all-the-icons-dired|unicode-fonts)' -- . ':!docs/superpowers/**'
```

Expected: no matches.

- [ ] **Step 6: Commit CI hardening**

```bash
git add .github/workflows/emacs-tests.yml \
  .github/workflows/windows-platform-tests.yml \
  test/p3-config-appearance-test.el
git commit -m "Harden appearance configuration checks"
```

---

### Task 6: Open the draft PR and perform exact-head automated verification

**Files:**
- No source file is required unless verification exposes a defect.
- PR body should reference the spec and plan.

**Interfaces:**
- Consumes: all prior implementation commits.
- Produces: draft PR #23 (or the next available PR number), exact-head Ubuntu and Windows evidence, and a bounded list of any remaining manual graphical checks.

- [ ] **Step 1: Push/open a draft PR without merging**

Use the existing branch `refactor/appearance-config`. The PR summary must state:

- Doom-modeline/all-the-icons/unicode-fonts removed;
- native mode line added;
- file/mode/remote/VC/Flycheck/coding/position information contract;
- Redisplay performance constraints;
- Nerd Font fallback behavior;
- theme deliberately unchanged;
- manual graphical acceptance still required.

- [ ] **Step 2: Verify exact-head Ubuntu Actions**

Confirm the Ubuntu `Emacs tests` run on the exact PR head passes:

- warnings-as-errors compile including `p3-config-appearance.el`;
- Appearance smoke load;
- existing subsystem smoke tests;
- full ERT suite including `p3-config-appearance-test.el`.

If it fails, retrieve the failing job log, fix the root cause, and rerun only the relevant bounded gate before the final full gate.

- [ ] **Step 3: Verify exact-head Windows Actions**

Confirm the Windows platform run on the exact same head passes:

- strict compile including Appearance;
- existing native Windows platform/terminal/editing checks;
- config architecture suite including Appearance tests.

Do not add graphical Windows CI machinery to chase visual rendering.

- [ ] **Step 4: Adversarially inspect the final diff**

Verify:

- no `p3-config-*` cross-module dependency;
- no project discovery or subprocess/file/remote I/O from `(:eval ...)` mode-line paths;
- no automatic font download;
- no hidden theme replacement;
- no UTF-8 or `.Rmd` coding change;
- no broad new cache/timer/framework;
- Dashboard/Dired behavior remains in Base while icon presentation is in Appearance;
- old icon/modeline package declarations are gone from active config.

Do not mark the PR ready to merge yet.

---

### Task 7: Graphical acceptance and minimal visual tuning

**Files:**
- Modify only `lisp/p3-config-appearance.el` if evidence requires spacing/threshold/face adjustments.
- Modify tests only when a behavior contract—not a screenshot preference—changes.

**Interfaces:**
- Consumes: exact-head automated-green implementation from Task 6.
- Produces: human-verified modern appearance on graphical Emacs and final reviewed head.

- [ ] **Step 1: Test the no-Nerd-Font fallback first if possible**

With `Symbols Nerd Font Mono` unavailable, start/reload normal graphical Emacs and verify:

- mode line remains readable with textual/Unicode file, mode, VC, diagnostic, and state fallbacks;
- Dashboard opens without tofu;
- Dired opens without tofu;
- no startup prompt tries to install a font.

- [ ] **Step 2: Install the Nerd Font explicitly and reload**

Use the package's normal interactive command:

```text
M-x nerd-icons-install-fonts
```

Restart Emacs only if the platform requires font discovery to refresh; otherwise run `C-c r`. Verify file and major-mode icons appear and Dashboard/Dired switch to the Nerd Icons path.

- [ ] **Step 3: Exercise the graphical acceptance matrix**

Check:

1. ordinary local project file on a Git branch;
2. modified file;
3. read-only buffer;
4. source buffer while Flycheck is running and after diagnostics finish;
5. buffer with meaningful `mode-line-process`;
6. narrow window;
7. remote/TRAMP buffer when an endpoint is available;
8. Dashboard;
9. Dired;
10. active versus inactive windows;
11. normal buffer containing `— → ✓ λ ∑`;
12. repeated `C-c r`.

There must be no noticeable typing, scrolling, or redisplay lag locally; remote/TRAMP rendering must not introduce noticeable latency.

- [ ] **Step 4: Make only evidence-driven visual adjustments**

Permitted tuning without reopening the design:

- spacing between existing segments;
- mode-line relative height/weight/box attributes;
- active/inactive contrast using theme-derived faces;
- the initial width thresholds `120/100/80`;
- fixed VC truncation bound near the 12-character target;
- individual Nerd glyph choice where the current glyph is visually unclear.

Do not add new segments, packages, timers, caches, or hard-coded palette colors as visual tuning.

- [ ] **Step 5: Re-run focused tests and exact-head CI after any tuning commit**

Any source adjustment requires:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-appearance-test.el \
  -f ert-run-tests-batch-and-exit
```

when local Emacs is available, followed by exact-head Ubuntu and Windows PR gates.

- [ ] **Step 6: Final adversarial review; stop before merge**

Confirm the implementation matches `docs/superpowers/specs/2026-09-05-appearance-config-design.md`, all exact-head automated gates are green, and the graphical acceptance matrix is complete. Report the final head SHA and remaining caveats, if any.

Do not merge without explicit approval.
