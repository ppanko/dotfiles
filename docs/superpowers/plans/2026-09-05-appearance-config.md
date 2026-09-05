# Appearance Configuration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the split appearance stack with one focused appearance owner, a lean Unicode + `nerd-icons` visual layer, and a modern native Emacs mode line without config-module coupling or redisplay latency.

**Architecture:** `config.org` remains the top-level composition map. `lisp/p3-config-appearance.el` becomes the visual owner for theme, fonts, frame chrome, mode-line formatting, icon availability, and Dashboard/Dired icon presentation; `lisp/p3-config-base.el` retains Dashboard/Dired/line-number behavior. The mode line reads already-available buffer/VC/Flycheck state and buffer-local project context derived outside redisplay.

**Tech Stack:** Emacs Lisp; `use-package`; built-in `mode-line-format`, `project.el`, VC, coding-system APIs and TRAMP path parsing; Flycheck state variables; `doom-themes`; `nerd-icons`; `nerd-icons-dired`; ERT; GitHub Actions on Ubuntu and Windows.

**Spec:** `docs/superpowers/specs/2026-09-05-appearance-config-design.md`

## Global Constraints

- Keep `doom-palenight` as the active theme.
- Keep Windows `Consolas` height `125` and GNU/Linux `Inconsolata` height `140`.
- Preserve maximized startup, bar cursor semantics, line-number activation, frame-title intent, matching-paren highlighting, Dashboard content, Dired behavior, UTF-8/process coding, and the `.Rmd` CRLF rule.
- Remove active `doom-modeline`, `all-the-icons`, `all-the-icons-dired`, and `unicode-fonts`; add only `nerd-icons` and `nerd-icons-dired` for this cleanup.
- File identity and major-mode identity must retain textual labels and use associated Nerd Font icons when available.
- Remote buffers must show textual host identity without initiating remote access.
- Do not recreate Doom-modeline environment/version probing. Existing mode-provided `mode-line-process` text may remain.
- Keep rendered VC payload bounded to 12 columns before ellipsis unless graphical acceptance demonstrates a nearby fixed bound is clearer.
- Emacs 30 uses `mode-line-format-right-align`; Emacs 29 uses one `space :align-to` fallback.
- No configuration module may require or call another `p3-config-*` module.
- No refresh timer, segment registry, extension protocol, generalized cache, or status-bar framework.
- Redisplay formatters must not call `project-current`, perform file/remote I/O, refresh VC, load packages, run subprocesses, or repeatedly scan fonts.
- Missing Nerd Font must leave mode line, Dashboard, and Dired text-safe. Never install fonts automatically at startup.
- Do not merge without explicit approval.

---

### Task 1: Pin the appearance boundary with RED ownership tests

**Files:**
- Create: `test/p3-config-appearance-test.el`
- Modify: `test/p3-config-test.el`

**Interfaces:**
- Consumes: repository source files through the source-reading test pattern already used by `test/p3-config-test.el`.
- Produces: structural regressions for the new owner, fifteenth explicit config module, removed legacy appearance packages, and no cross-config-module coupling.

- [ ] **Step 1: Create the focused structural test file**

Create `test/p3-config-appearance-test.el`:

```elisp
;;; p3-config-appearance-test.el --- Appearance configuration tests -*- lexical-binding: t; -*-

(require 'cl-lib)
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

(defun p3-config-appearance-test--count (needle contents)
  (let ((start 0) (count 0) (regexp (regexp-quote needle)))
    (while (string-match regexp contents start)
      (setq count (1+ count)
            start (match-end 0)))
    count))

(ert-deftest p3-config-appearance-has-one-top-level-owner ()
  (let ((config (p3-config-appearance-test--contents "config.org")))
    (should (= 1
               (p3-config-appearance-test--count
                "(p3/config-load-module 'p3-config-appearance)"
                config)))))

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

- [ ] **Step 2: Update the global module count and readable order**

In `test/p3-config-test.el`:

- rename `p3-config-org-source-loads-fourteen-config-modules` to `p3-config-org-source-loads-fifteen-config-modules`;
- change the expected config-loader count from `14` to `15`;
- add `p3-config-appearance` to the explicit module list;
- add `appearance` to `p3-config-early-orchestration-order-is-explicit` and assert:

```elisp
(should (< rtools base))
(should (< base appearance))
(should (< appearance editing))
```

This order is only the human-readable top-level map. The focused test separately forbids module dependency/calls.

- [ ] **Step 3: Run the focused RED gate**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-test.el \
  -l test/p3-config-appearance-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: FAIL because `lisp/p3-config-appearance.el` and its loader do not yet exist and the module count is still 14.

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
- Modify: `test/p3-config-appearance-test.el`
- Modify: `test/p3-config-test.el`

**Interfaces:**
- Consumes: `use-package`; built-in face/frame APIs; Dashboard variables; `nerd-icons-font-family`; `nerd-icons-dired-mode`.
- Produces: `p3/appearance--icons-available`, `p3/appearance-refresh-icon-availability`, `p3/appearance-configure-dashboard-icons`, `p3/appearance-sync-dired-icons`, and feature `p3-config-appearance`.

- [ ] **Step 1: Extend the RED structural assertions**

Add to `p3-config-appearance-owns-visual-stack`:

```elisp
(should (string-match-p "dashboard-icon-type" appearance))
(should (string-match-p "nerd-icons-dired-mode" appearance))
(should-not (string-match-p "dashboard-icon-type" base))
(should-not (string-match-p "all-the-icons-dired-mode" base))
(should (string-match-p "initial-scratch-message" base))
(should (string-match-p "ring-bell-function" base))
(should (string-match-p "default-process-coding-system" config))
(should (string-match-p "\\\\.Rmd" config))
```

Run the Task 1 gate again. Expected: FAIL on current inline/icon ownership.

- [ ] **Step 2: Create the Appearance owner and warning-clean declarations**

Start `lisp/p3-config-appearance.el` with:

```elisp
;;; p3-config-appearance.el --- Visual presentation configuration -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'project)
(require 'subr-x)
(require 'use-package)

(defvar dashboard-icon-type)
(defvar dashboard-set-heading-icons)
(defvar dashboard-set-file-icons)
(defvar nerd-icons-font-family)
(defvar flycheck-mode)
(defvar flycheck-last-status-change)
(defvar flycheck-current-errors)

(declare-function nerd-icons-icon-for-file "nerd-icons" (file &rest args))
(declare-function nerd-icons-icon-for-buffer "nerd-icons" (&rest args))
(declare-function nerd-icons-icon-for-mode "nerd-icons" (mode &rest args))
(declare-function nerd-icons-octicon "nerd-icons" (name &rest args))
(declare-function nerd-icons-codicon "nerd-icons" (name &rest args))
(declare-function nerd-icons-dired-mode "nerd-icons-dired" (&optional arg))
(declare-function flycheck-count-errors "flycheck" (errors))

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
```

- [ ] **Step 3: Move frame/theme/font presentation into Appearance**

Add:

```elisp
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

(setq frame-title-format "%b"
      show-paren-when-point-inside-paren t)
(show-paren-mode t)

(set-face-attribute 'mode-line nil :box nil :weight 'semi-bold)
(set-face-attribute 'mode-line-inactive nil :box nil :weight 'normal)
(set-face-attribute 'line-number-current-line nil :weight 'bold)
```

Do not set literal foreground/background colors.

- [ ] **Step 4: Add the single icon framework and text-safe reconciliation**

Add:

```elisp
(use-package nerd-icons
  :demand t
  :custom
  (nerd-icons-font-family "Symbols Nerd Font Mono")
  :config
  (p3/appearance-refresh-icon-availability))

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
  "Reconcile the Dired icon hook with current font availability."
  (remove-hook 'dired-mode-hook #'nerd-icons-dired-mode)
  (when p3/appearance--icons-available
    (add-hook 'dired-mode-hook #'nerd-icons-dired-mode)))

(p3/appearance-sync-dired-icons)
```

Do not call `nerd-icons-install-fonts`.

- [ ] **Step 5: Reduce Base to nonvisual behavior**

In `lisp/p3-config-base.el`:

- remove maximized-frame, platform font, and cursor settings;
- remove `all-the-icons-scale-factor`, `all-the-icons-install-fonts`, `all-the-icons`, and `all-the-icons-dired`;
- remove Dashboard's `dashboard-icon-type` assignment;
- remove `:after all-the-icons-dired` and the `all-the-icons-dired-mode` Dired hook;
- keep Dashboard content/setup and Dired behavior;
- keep `p3/set-line-numbers`, removing only its hard-coded `set-face-foreground` call;
- add:

```elisp
(setq inhibit-startup-message t
      initial-scratch-message nil
      initial-major-mode 'lisp-interaction-mode
      ring-bell-function #'ignore)
```

- [ ] **Step 6: Replace inline appearance with one top-level loader**

Add after Base in `config.org`:

```org
* Appearance

Theme, fonts, frame chrome, mode-line presentation, and icon presentation live
in =lisp/p3-config-appearance.el=.

#+BEGIN_SRC emacs-lisp
  (p3/config-load-module 'p3-config-appearance)
#+END_SRC
```

Remove the inline `Themes` implementation, Doom-modeline block, commented Telephone Line block, and `unicode-fonts` declaration. Keep the UTF-8/process coding block and `.Rmd` CRLF rule under an encoding-focused heading.

- [ ] **Step 7: Run ownership tests GREEN**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-test.el \
  -l test/p3-config-appearance-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS for structural ownership/extraction tests.

- [ ] **Step 8: Commit the visual extraction**

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
- Consumes: `buffer-file-name`, `default-directory`, `major-mode`, `mode-name`, `mode-line-process`, `file-remote-p`, `project-current` only outside redisplay, and Nerd Icons functions only when cached icon availability is true.
- Produces: buffer-local `p3/appearance--project-root`, `p3/appearance--project-relative-file`; `p3/appearance-refresh-buffer-context`; `p3/appearance--remote-host`; `p3/appearance--buffer-state`; `p3/appearance--file-segment`; `p3/appearance--mode-segment`; `p3/appearance--position-segment`; `p3/appearance--left-segment`; initial `p3/appearance--right-segment`; `p3/appearance--native-right-align-p`; `p3/appearance--right-align-space`; `p3/appearance--build-mode-line-format`.

- [ ] **Step 1: Add the runtime test harness and RED identity tests**

At the top of `test/p3-config-appearance-test.el`, after structural helpers, load the real module with external surfaces stubbed:

```elisp
(require 'use-package-ensure)
(setq use-package-ensure-function (lambda (&rest _) t))

(defvar nerd-icons-font-family "Symbols Nerd Font Mono")
(defun nerd-icons-icon-for-file (&rest _) "F")
(defun nerd-icons-icon-for-buffer (&rest _) "B")
(defun nerd-icons-icon-for-mode (&rest _) "M")
(defun nerd-icons-octicon (&rest _) "G")
(defun nerd-icons-codicon (&rest _) "R")
(provide 'nerd-icons)

(let ((real-load-theme (symbol-function 'load-theme)))
  (unwind-protect
      (progn
        (fset 'load-theme (lambda (&rest _) t))
        (provide 'doom-themes)
        (load-file
         (expand-file-name "lisp/p3-config-appearance.el"
                           p3-config-appearance-test--root)))
    (fset 'load-theme real-load-theme)))
```

Add:

```elisp
(ert-deftest p3-appearance-file-segment-keeps-text-without-icons ()
  (with-temp-buffer
    (setq buffer-file-name "/tmp/project/src/example.R"
          p3/appearance--icons-available nil
          p3/appearance--project-relative-file "src/example.R")
    (should (string-match-p "src/example\\.R"
                            (p3/appearance--file-segment)))))

(ert-deftest p3-appearance-remote-host-is-textual ()
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

Add two tests that `cl-letf` `p3/appearance--native-right-align-p` to return `t` and `nil`, respectively, and assert the built format contains `mode-line-format-right-align` only on the native path.

Run the focused appearance test file. Expected: FAIL because formatter/cache functions are not defined.

- [ ] **Step 2: Derive project context outside redisplay**

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
    (when-let* ((project
                 (project-current nil (file-name-directory buffer-file-name)))
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

Formatters read these variables and never call `project-current`.

- [ ] **Step 3: Implement file/mode/remote/buffer-state segments**

Use these concrete rules:

```elisp
(defun p3/appearance--remote-host ()
  (file-remote-p (or buffer-file-name default-directory) 'host))

(defun p3/appearance--buffer-state ()
  (cond
   (buffer-read-only (propertize "RO" 'face 'shadow))
   ((buffer-modified-p) (propertize "●" 'face 'warning))
   (t "")))

(defun p3/appearance--file-label ()
  (cond
   ((not buffer-file-name) (buffer-name))
   ((file-remote-p buffer-file-name)
    (file-name-nondirectory buffer-file-name))
   ((and (>= (window-total-width) 120)
         p3/appearance--project-relative-file)
    p3/appearance--project-relative-file)
   (t (file-name-nondirectory buffer-file-name))))
```

`p3/appearance--file-segment` prefixes `nerd-icons-icon-for-file` or `nerd-icons-icon-for-buffer` only when `p3/appearance--icons-available` is non-nil; otherwise it returns text only. `p3/appearance--mode-segment` uses `nerd-icons-icon-for-mode major-mode` only on the icon path and always appends `(format-mode-line mode-name)`.

Remote host identity is a separate textual segment; when icons are available prefix it with `nerd-icons-codicon "nf-cod-remote"`. File/mode/icon calls must be wrapped in `condition-case` so lookup failures fall back to text.

- [ ] **Step 4: Add the initial position-only right side and alignment**

Define:

```elisp
(defun p3/appearance--position-segment ()
  (format-mode-line "%l:%c"))

(defun p3/appearance--right-segment ()
  (p3/appearance--position-segment))

(defun p3/appearance--native-right-align-p ()
  (boundp 'mode-line-format-right-align))

(defun p3/appearance--right-align-space ()
  (let ((width (string-width (p3/appearance--right-segment))))
    (propertize " " 'display
                `((space :align-to (- right ,(+ width 1)))))))
```

`p3/appearance--left-segment` joins nonempty buffer state, remote host, file identity, mode identity, and—only at widths `>= 100`—`(format-mode-line mode-line-process)`.

Define:

```elisp
(defun p3/appearance--build-mode-line-format ()
  (append
   '("%e " (:eval (p3/appearance--left-segment)))
   (if (p3/appearance--native-right-align-p)
       '(mode-line-format-right-align)
     '((:eval (p3/appearance--right-align-space))))
   '((:eval (p3/appearance--right-segment)) " ")))

(setq-default mode-line-format (p3/appearance--build-mode-line-format))
(when (boundp 'mode-line-right-align-edge)
  (setq-default mode-line-right-align-edge 'window))
```

Using `setq-default` leaves existing buffer-local mode-line formats alone.

- [ ] **Step 5: Run identity/alignment GREEN and commit**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-appearance-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS.

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
- Consumes: `vc-mode`; `flycheck-last-status-change`, `flycheck-current-errors`, `flycheck-count-errors` only when Flycheck is already loaded; `buffer-file-coding-system`; `window-total-width`.
- Produces: `p3/appearance--vc-segment`, `p3/appearance--flycheck-finished-segment`, `p3/appearance--flycheck-segment`, `p3/appearance--coding-segment`, and completed `p3/appearance--right-segment`.

- [ ] **Step 1: Add RED state and performance tests**

Add ERT cases for:

- `vc-mode` nil → nil VC segment;
- long VC text → `string-width <= 14` including the textual separator and ellipsis;
- Flycheck `running` → progress state without stale counts;
- `finished` + zero counts → success;
- `finished` + error/warning/info counts → all nonzero counts;
- `errored`, `suspicious`, `interrupted` → distinct compact states;
- `no-checker`, `not-checked`, Flycheck absent/disabled → nil;
- `utf-8-unix` → `UTF-8 LF`;
- `utf-8-dos` → `UTF-8 CRLF`;
- position remains present at every width.

Add redisplay guards:

```elisp
(cl-letf (((symbol-function 'project-current)
           (lambda (&rest _) (ert-fail "project-current during redisplay")))
          ((symbol-function 'process-file)
           (lambda (&rest _) (ert-fail "process-file during redisplay"))))
  (format-mode-line (default-value 'mode-line-format)))
```

For a remote buffer, additionally stub `file-exists-p`, `file-attributes`, and `directory-files` to `ert-fail` while formatting. Add a test that binds `p3/appearance--icons-available` nil and stubs each `nerd-icons-*` formatter to fail; rendering must still succeed.

Run the focused test file. Expected: FAIL because status functions are not implemented.

- [ ] **Step 2: Implement bounded VC presentation**

Add:

```elisp
(defun p3/appearance--git-icon ()
  (if p3/appearance--icons-available
      (condition-case nil
          (nerd-icons-octicon "nf-oct-git_branch" :height 0.95)
        (error "Git"))
    "Git"))

(defun p3/appearance--vc-segment ()
  (when vc-mode
    (let* ((raw (string-trim (format-mode-line vc-mode)))
           (text (truncate-string-to-width raw 12 nil nil "…")))
      (format "%s %s" (p3/appearance--git-icon) text))))
```

Do not call `vc-refresh-state`, Git, or Magit.

- [ ] **Step 3: Implement Flycheck state mapping from existing state only**

Add:

```elisp
(defun p3/appearance--flycheck-finished-segment (&optional compact)
  (let* ((counts (flycheck-count-errors flycheck-current-errors))
         (errors (or (cdr (assq 'error counts)) 0))
         (warnings (or (cdr (assq 'warning counts)) 0))
         (infos (or (cdr (assq 'info counts)) 0)))
    (cond
     ((and (zerop errors) (zerop warnings) (zerop infos))
      (propertize "✓" 'face 'success))
     (compact
      (cond
       ((> errors 0) (propertize (format "×%d" errors) 'face 'error))
       ((> warnings 0) (propertize (format "!%d" warnings) 'face 'warning))
       (t (format "i%d" infos))))
     (t
      (string-join
       (delq nil
             (list (when (> errors 0)
                     (propertize (format "×%d" errors) 'face 'error))
                   (when (> warnings 0)
                     (propertize (format "!%d" warnings) 'face 'warning))
                   (when (> infos 0) (format "i%d" infos))))
       " ")))))

(defun p3/appearance--flycheck-segment (&optional compact)
  (when (and (featurep 'flycheck)
             (bound-and-true-p flycheck-mode))
    (pcase flycheck-last-status-change
      ('running (propertize "↻" 'face 'shadow))
      ('finished (p3/appearance--flycheck-finished-segment compact))
      ('errored (propertize "×" 'face 'error))
      ('suspicious (propertize "?" 'face 'warning))
      ('interrupted (propertize "·" 'face 'shadow))
      ((or 'no-checker 'not-checked) nil)
      (_ nil))))
```

No Flycheck `require`, checker execution, or refresh is permitted from these functions.

- [ ] **Step 4: Implement coding and completed right-side width policy**

Add:

```elisp
(defun p3/appearance--coding-segment ()
  (let* ((coding buffer-file-coding-system)
         (base (coding-system-base coding))
         (encoding
          (if (memq base '(utf-8 utf-8-unix utf-8-dos utf-8-mac))
              "UTF-8"
            (upcase (symbol-name base))))
         (eol (pcase (coding-system-eol-type coding)
                (0 "LF")
                (1 "CRLF")
                (2 "CR")
                (_ nil))))
    (string-join (delq nil (list encoding eol)) " ")))

(defun p3/appearance--right-segment ()
  (let* ((width (window-total-width))
         (vc (p3/appearance--vc-segment))
         (flycheck (p3/appearance--flycheck-segment (< width 80)))
         (coding (and (>= width 100) (p3/appearance--coding-segment)))
         (position (p3/appearance--position-segment)))
    (string-join (delq nil (list vc flycheck coding position)) "  ")))
```

The left-side file label already drops project-parent detail below 120 columns; `mode-line-process` is already omitted below 100 columns. Position, actual filename, remote host, and mode identity remain.

- [ ] **Step 5: Run GREEN performance/state tests and commit**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-appearance-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS, including the expensive-operation guards.

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
- Consumes: completed Appearance module/tests.
- Produces: reload idempotency regression, warnings-as-errors compilation on Ubuntu/Windows, batch smoke load, and full ERT inclusion.

- [ ] **Step 1: Add reload/idempotency regression**

Load the real appearance source twice with icon availability forced false and assert:

```elisp
(should (= 1 (cl-count #'p3/appearance-refresh-buffer-context
                       find-file-hook :test #'eq)))
(should (= 1 (cl-count #'p3/appearance-refresh-buffer-context
                       after-change-major-mode-hook :test #'eq)))
(should-not (memq #'nerd-icons-dired-mode dired-mode-hook))
(should (equal (default-value 'mode-line-format)
               (p3/appearance--build-mode-line-format)))
```

Then bind/set `p3/appearance--icons-available` true, call `p3/appearance-sync-dired-icons` twice, and assert exactly one `nerd-icons-dired-mode` entry in `dired-mode-hook`.

Run the focused appearance suite. Expected: PASS.

- [ ] **Step 2: Extend Ubuntu compilation, smoke, and ERT coverage**

In `.github/workflows/emacs-tests.yml`:

- add `lisp/p3-config-appearance.el` to warnings-as-errors compilation;
- add `-l test/p3-config-appearance-test.el` to the full ERT command;
- add this smoke step before full ERT:

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
  --eval '(defun nerd-icons-octicon (&rest _) "G")' \
  --eval '(defun nerd-icons-codicon (&rest _) "R")' \
  --eval '(fset (quote load-theme) (lambda (&rest _) t))' \
  -l lisp/p3-config-appearance.el \
  --eval '(unless (and (featurep (quote p3-config-appearance)) (listp (default-value (quote mode-line-format)))) (kill-emacs 1))'
```

Expected: exit 0 without graphical display or Nerd Font.

- [ ] **Step 3: Extend Windows source/compile/test coverage**

In `.github/workflows/windows-platform-tests.yml`:

- add `lisp/p3-config-appearance.el` and `test/p3-config-appearance-test.el` to `pull_request.paths`;
- add `lisp/p3-config-appearance.el` to strict Windows byte compilation;
- add `-l test/p3-config-appearance-test.el` to the Windows config-architecture ERT step.

Do not add graphical font rendering to Windows Actions.

- [ ] **Step 4: Run available local/static gates**

Run the focused suite and, if the execution environment has Emacs, the full local ERT command matching `.github/workflows/emacs-tests.yml`.

Run:

```bash
git grep -n -E '\(use-package (doom-modeline|all-the-icons|all-the-icons-dired|unicode-fonts)' -- . ':!docs/superpowers/**'
```

Expected: no active-source matches.

- [ ] **Step 5: Commit CI hardening**

```bash
git add .github/workflows/emacs-tests.yml \
  .github/workflows/windows-platform-tests.yml \
  test/p3-config-appearance-test.el
git commit -m "Harden appearance configuration checks"
```

---

### Task 6: Open the draft PR and verify the exact automated head

**Files:**
- No source modification unless verification exposes a defect.

**Interfaces:**
- Consumes: implementation commits from Tasks 1–5.
- Produces: draft PR, exact-head Ubuntu/Windows evidence, and the remaining manual graphical acceptance requirement.

- [ ] **Step 1: Open a draft PR without merging**

Use branch `refactor/appearance-config`. The body must state:

- Doom-modeline/all-the-icons/unicode-fonts removal;
- custom native mode line and information contract;
- file/mode/remote/VC/Flycheck/coding/position behavior;
- redisplay performance constraints;
- Nerd Font fallback behavior;
- unchanged `doom-palenight` theme;
- manual graphical acceptance still required.

- [ ] **Step 2: Verify exact-head Ubuntu Actions**

Confirm the exact PR head passes:

- warnings-as-errors compile including Appearance;
- Appearance batch smoke;
- existing subsystem smokes;
- full ERT including Appearance tests.

On failure, retrieve the failing job log, fix the root cause, run the smallest relevant gate, then rerun the final full gate.

- [ ] **Step 3: Verify exact-head Windows Actions**

Confirm the same head passes strict Appearance compilation and the config architecture suite including Appearance tests, alongside existing native Windows checks.

- [ ] **Step 4: Adversarially inspect the final automated diff**

Verify:

- no `p3-config-*` cross-module dependency;
- no project discovery, subprocess, file/remote I/O, package load, or VC refresh from mode-line eval paths;
- no automatic font download;
- no hidden theme replacement;
- no UTF-8 or `.Rmd` coding change;
- no broad cache/timer/framework;
- Dashboard/Dired behavior stays in Base while icon presentation stays in Appearance;
- legacy modeline/icon/font package declarations are gone from active config.

Do not mark merge-ready yet.

---

### Task 7: Perform graphical acceptance and minimal visual tuning

**Files:**
- Modify only `lisp/p3-config-appearance.el` for evidence-driven spacing/threshold/face/glyph adjustments.
- Modify tests only if a behavioral contract changes.

**Interfaces:**
- Consumes: automated-green exact head from Task 6.
- Produces: human-verified graphical appearance and final reviewed head.

- [ ] **Step 1: Verify the missing-font fallback**

With `Symbols Nerd Font Mono` unavailable, start/reload graphical Emacs and verify:

- textual/Unicode mode line is readable;
- Dashboard and Dired open without tofu;
- no startup font-install prompt/action occurs.

- [ ] **Step 2: Install the Nerd Font explicitly and reload**

Run:

```text
M-x nerd-icons-install-fonts
```

Restart Emacs only if platform font discovery requires it; otherwise run `C-c r`. Verify file and major-mode icons appear and Dashboard/Dired use Nerd Icons.

- [ ] **Step 3: Exercise the graphical matrix**

Check all twelve cases:

1. local project file on a Git branch;
2. modified file;
3. read-only buffer;
4. Flycheck running and finished-with-diagnostics states;
5. buffer with meaningful `mode-line-process`;
6. narrow window;
7. remote/TRAMP buffer when an endpoint is available;
8. Dashboard;
9. Dired;
10. active versus inactive windows;
11. normal text buffer containing `— → ✓ λ ∑`;
12. repeated `C-c r`.

There must be no noticeable typing, scrolling, or redisplay lag locally; remote rendering must not add noticeable latency.

- [ ] **Step 4: Make only permitted evidence-driven visual adjustments**

Permitted without reopening design:

- segment spacing;
- mode-line relative height/weight/box attributes;
- active/inactive contrast using theme-derived faces;
- width thresholds `120/100/80`;
- fixed VC bound near 12 columns;
- individual Nerd glyph choice when the current glyph is unclear.

Do not add segments, packages, timers, generalized caches, or literal palette colors.

- [ ] **Step 5: Re-run focused and exact-head gates after any source tuning**

When local Emacs exists:

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-appearance-test.el \
  -f ert-run-tests-batch-and-exit
```

Then require fresh exact-head Ubuntu and Windows PR gates.

- [ ] **Step 6: Final adversarial review and stop before merge**

Confirm the implementation matches the approved spec, the exact-head automated gates are green, and the graphical matrix is complete. Report final head SHA and any remaining caveat.

Do not merge without explicit approval.
