# Appearance Configuration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the split appearance stack with one focused appearance owner, a lean Unicode + `nerd-icons` visual layer, and a modern native Emacs mode line without config-module coupling or redisplay latency.

**Architecture:** `config.org` remains the composition map. `lisp/p3-config-appearance.el` owns theme, fonts, frame chrome, native mode-line formatting, icon availability, and Dashboard/Dired icon presentation; `lisp/p3-config-base.el` retains Dashboard/Dired/line-number behavior. Mode-line redisplay reads existing buffer/VC/Flycheck state and buffer-local project context derived outside redisplay.

**Tech Stack:** Emacs Lisp; `use-package`; built-in `mode-line-format`, `project.el`, VC, coding-system APIs and TRAMP path parsing; Flycheck state; `doom-themes`; `nerd-icons`; `nerd-icons-dired`; ERT; GitHub Actions on Ubuntu and Windows.

**Spec:** `docs/superpowers/specs/2026-09-05-appearance-config-design.md`

## Global Constraints

- Keep `doom-palenight`.
- Keep Windows `Consolas` height `125` and GNU/Linux `Inconsolata` height `140`.
- Preserve maximized startup, bar cursor semantics, line-number activation, frame title, matching-paren highlighting, Dashboard content, Dired behavior, UTF-8/process coding, and `.Rmd` CRLF policy.
- Remove active `doom-modeline`, `all-the-icons`, `all-the-icons-dired`, and `unicode-fonts`; add only `nerd-icons` and `nerd-icons-dired` for this cleanup.
- File and major-mode identity always keep text; Nerd Font icons supplement them when available.
- Remote buffers show host text without remote filesystem access.
- Do not recreate Doom-modeline environment/version probing. Existing `mode-line-process` text may remain.
- Bound VC payload to 12 columns before ellipsis unless graphical acceptance justifies a nearby fixed bound.
- Emacs 30 uses `mode-line-format-right-align`; Emacs 29 uses one `space :align-to` fallback.
- No `p3-config-*` module may require/call another `p3-config-*` module.
- No refresh timer, segment registry, extension protocol, generalized cache, or status-bar framework.
- Redisplay must not call `project-current`, perform file/remote I/O, refresh VC, load packages, run subprocesses, or repeatedly scan fonts.
- Missing Nerd Font must leave mode line, Dashboard, and Dired text-safe. Never install fonts automatically.
- Do not merge without explicit approval.

---

### Task 1: Pin the appearance boundary with RED ownership tests

**Files:**
- Create: `test/p3-config-appearance-test.el`
- Modify: `test/p3-config-test.el`

**Interfaces:**
- Consumes: repository source files through the existing source-reading test pattern.
- Produces: structural regressions for the new owner, fifteenth explicit config module, legacy-package removal, and no config-module coupling.

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
                       "doom-palenight"))
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

- [ ] **Step 2: Update global module count/order**

In `test/p3-config-test.el`:

- rename `p3-config-org-source-loads-fourteen-config-modules` to `p3-config-org-source-loads-fifteen-config-modules`;
- change `14` to `15`;
- add `p3-config-appearance` to the explicit list;
- in `p3-config-early-orchestration-order-is-explicit`, add:

```elisp
(appearance
 (p3-config-test--position
  "(p3/config-load-module 'p3-config-appearance)" contents))
```

and assert:

```elisp
(should (< rtools base))
(should (< base appearance))
(should (< appearance editing))
```

- [ ] **Step 3: Verify RED**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-test.el \
  -l test/p3-config-appearance-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: FAIL because the Appearance owner/loader does not exist and the module count is still 14.

- [ ] **Step 4: Commit RED tests**

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
- Consumes: `use-package`, frame/face APIs, Dashboard variables, `nerd-icons-font-family`, `nerd-icons-dired-mode`.
- Produces: `p3/appearance--icons-available`, `p3/appearance-refresh-icon-availability`, `p3/appearance-configure-dashboard-icons`, `p3/appearance-sync-dired-icons`, feature `p3-config-appearance`.

- [ ] **Step 1: Extend structural tests and verify RED**

Add inside `p3-config-appearance-owns-visual-stack`:

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

Run the Task 1 command. Expected: FAIL on current inline/icon ownership.

- [ ] **Step 2: Create warning-clean Appearance owner**

Create `lisp/p3-config-appearance.el`:

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

(defvar p3/appearance--icons-available nil)

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

(setq frame-title-format "%b"
      show-paren-when-point-inside-paren t)
(show-paren-mode t)

(set-face-attribute 'mode-line nil :box nil :weight 'semi-bold)
(set-face-attribute 'mode-line-inactive nil :box nil :weight 'normal)
(set-face-attribute 'line-number-current-line nil :weight 'bold)

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

(provide 'p3-config-appearance)
;;; p3-config-appearance.el ends here
```

No literal palette colors and no `nerd-icons-install-fonts`.

- [ ] **Step 3: Reduce Base to nonvisual behavior**

In `lisp/p3-config-base.el` remove maximized-frame/font/cursor settings, `all-the-icons*` declarations and Dired icon hook, Dashboard `dashboard-icon-type`, and the line-number `set-face-foreground` call. Keep Dashboard content/setup, Dired behavior, and line-number activation.

Add exactly:

```elisp
(setq inhibit-startup-message t
      initial-scratch-message nil
      initial-major-mode 'lisp-interaction-mode
      ring-bell-function #'ignore)
```

- [ ] **Step 4: Replace inline appearance with one loader**

Add after Base in `config.org`:

```org
* Appearance

Theme, fonts, frame chrome, mode-line presentation, and icon presentation live
in =lisp/p3-config-appearance.el=.

#+BEGIN_SRC emacs-lisp
  (p3/config-load-module 'p3-config-appearance)
#+END_SRC
```

Remove the old inline `Themes` implementation, Doom-modeline, commented Telephone Line block, and `unicode-fonts`. Keep UTF-8/process coding and `.Rmd` CRLF under an encoding-focused heading.

- [ ] **Step 5: Run GREEN ownership gate**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-test.el \
  -l test/p3-config-appearance-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add config.org lisp/p3-config-base.el lisp/p3-config-appearance.el \
  test/p3-config-test.el test/p3-config-appearance-test.el
git commit -m "Extract appearance and icon configuration"
```

---

### Task 3: Build native mode-line identity and alignment

**Files:**
- Modify: `lisp/p3-config-appearance.el`
- Modify: `test/p3-config-appearance-test.el`

**Interfaces:**
- Produces: `p3/appearance--project-root`, `p3/appearance--project-relative-file`, `p3/appearance-refresh-buffer-context`, `p3/appearance--join`, `p3/appearance--safe-icon`, `p3/appearance--remote-host`, `p3/appearance--buffer-state`, `p3/appearance--file-label`, `p3/appearance--file-segment`, `p3/appearance--remote-segment`, `p3/appearance--mode-segment`, `p3/appearance--position-segment`, `p3/appearance--left-segment`, initial `p3/appearance--right-segment`, `p3/appearance--native-right-align-p`, `p3/appearance--right-align-space`, `p3/appearance--build-mode-line-format`.

- [ ] **Step 1: Add reusable runtime test loader**

Before runtime ERT cases in `test/p3-config-appearance-test.el`, add:

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
(provide 'doom-themes)

(defun p3-config-appearance-test--load-appearance ()
  (let ((real-load-theme (symbol-function 'load-theme)))
    (unwind-protect
        (progn
          (fset 'load-theme (lambda (&rest _) t))
          (load-file
           (expand-file-name "lisp/p3-config-appearance.el"
                             p3-config-appearance-test--root)))
      (fset 'load-theme real-load-theme))))

(p3-config-appearance-test--load-appearance)
```

- [ ] **Step 2: Add RED identity/alignment tests**

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

(ert-deftest p3-appearance-mode-segment-keeps-text-without-icons ()
  (with-temp-buffer
    (emacs-lisp-mode)
    (let ((p3/appearance--icons-available nil))
      (should (string-match-p "Emacs-Lisp"
                              (p3/appearance--mode-segment))))))

(ert-deftest p3-appearance-build-mode-line-selects-native-alignment ()
  (cl-letf (((symbol-function 'p3/appearance--native-right-align-p)
             (lambda () t)))
    (should (memq 'mode-line-format-right-align
                  (p3/appearance--build-mode-line-format)))))

(ert-deftest p3-appearance-build-mode-line-selects-emacs29-fallback ()
  (cl-letf (((symbol-function 'p3/appearance--native-right-align-p)
             (lambda () nil)))
    (let ((format (p3/appearance--build-mode-line-format)))
      (should-not (memq 'mode-line-format-right-align format))
      (should (string-match-p "p3/appearance--right-align-space"
                              (prin1-to-string format))))))
```

Run focused Appearance ERT. Expected: FAIL because formatter functions do not exist.

- [ ] **Step 3: Implement project cache and identity helpers**

Append to Appearance before `provide`:

```elisp
(defvar-local p3/appearance--project-root nil)
(defvar-local p3/appearance--project-relative-file nil)

(defun p3/appearance-refresh-buffer-context ()
  "Refresh cheap local project presentation context."
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

(defun p3/appearance--join (&rest segments)
  (string-join
   (delq nil
         (mapcar (lambda (segment)
                   (and segment
                        (not (string-empty-p segment))
                        segment))
                 segments))
   "  "))

(defun p3/appearance--safe-icon (function &rest args)
  (when p3/appearance--icons-available
    (condition-case nil
        (apply function args)
      (error nil))))

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

(defun p3/appearance--file-segment ()
  (let ((icon
         (if buffer-file-name
             (p3/appearance--safe-icon
              #'nerd-icons-icon-for-file buffer-file-name :height 0.95)
           (p3/appearance--safe-icon
            #'nerd-icons-icon-for-buffer :height 0.95))))
    (p3/appearance--join icon (p3/appearance--file-label))))

(defun p3/appearance--remote-segment ()
  (when-let ((host (p3/appearance--remote-host)))
    (p3/appearance--join
     (p3/appearance--safe-icon
      #'nerd-icons-codicon "nf-cod-remote" :height 0.95)
     host)))

(defun p3/appearance--mode-segment ()
  (p3/appearance--join
   (p3/appearance--safe-icon
    #'nerd-icons-icon-for-mode major-mode :height 0.95)
   (format-mode-line mode-name)))
```

`project-current` is used only in the refresh hook, never in a mode-line formatter.

- [ ] **Step 4: Implement left/right identity and alignment**

Append:

```elisp
(defun p3/appearance--position-segment ()
  (format-mode-line "%l:%c"))

(defun p3/appearance--left-segment ()
  (let ((process
         (and (>= (window-total-width) 100)
              mode-line-process
              (string-trim (format-mode-line mode-line-process)))))
    (p3/appearance--join
     (p3/appearance--buffer-state)
     (p3/appearance--remote-segment)
     (p3/appearance--file-segment)
     (p3/appearance--mode-segment)
     process)))

(defun p3/appearance--right-segment ()
  (p3/appearance--position-segment))

(defun p3/appearance--native-right-align-p ()
  (boundp 'mode-line-format-right-align))

(defun p3/appearance--right-align-space ()
  (let ((width (string-width (p3/appearance--right-segment))))
    (propertize " " 'display
                `((space :align-to (- right ,(+ width 1)))))))

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

- [ ] **Step 5: Run GREEN and commit**

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

### Task 4: Add VC, Flycheck, coding, narrow-width policy, and redisplay guards

**Files:**
- Modify: `lisp/p3-config-appearance.el`
- Modify: `test/p3-config-appearance-test.el`

**Interfaces:**
- Produces: `p3/appearance--git-icon`, `p3/appearance--vc-text`, `p3/appearance--vc-segment`, `p3/appearance--flycheck-finished-segment`, `p3/appearance--flycheck-segment`, `p3/appearance--coding-segment`, completed `p3/appearance--right-segment`.

- [ ] **Step 1: Add exact RED status tests**

Add:

```elisp
(ert-deftest p3-appearance-vc-text-is-bounded ()
  (with-temp-buffer
    (setq vc-mode " Git:very-long-branch-name")
    (should (<= (string-width (p3/appearance--vc-text)) 12))))

(ert-deftest p3-appearance-flycheck-finished-renders-counts ()
  (let ((features (cons 'flycheck features))
        (flycheck-mode t)
        (flycheck-last-status-change 'finished)
        (flycheck-current-errors 'simulated))
    (cl-letf (((symbol-function 'flycheck-count-errors)
               (lambda (_errors)
                 '((error . 2) (warning . 3) (info . 1)))))
      (let ((segment (p3/appearance--flycheck-segment)))
        (should (string-match-p "2" segment))
        (should (string-match-p "3" segment))
        (should (string-match-p "1" segment))))))

(ert-deftest p3-appearance-flycheck-finished-renders-clean ()
  (let ((features (cons 'flycheck features))
        (flycheck-mode t)
        (flycheck-last-status-change 'finished)
        (flycheck-current-errors nil))
    (cl-letf (((symbol-function 'flycheck-count-errors)
               (lambda (_errors) nil)))
      (should (string-match-p "✓" (p3/appearance--flycheck-segment))))))

(ert-deftest p3-appearance-flycheck-statuses-are-deliberate ()
  (let ((features (cons 'flycheck features))
        (flycheck-mode t))
    (dolist (case '((running . "↻")
                    (errored . "×")
                    (suspicious . "?")
                    (interrupted . "·")))
      (let ((flycheck-last-status-change (car case)))
        (should (string-match-p
                 (regexp-quote (cdr case))
                 (p3/appearance--flycheck-segment)))))
    (dolist (status '(no-checker not-checked))
      (let ((flycheck-last-status-change status))
        (should-not (p3/appearance--flycheck-segment))))))

(ert-deftest p3-appearance-flycheck-absent-or-disabled-is-hidden ()
  (let ((features (delq 'flycheck (copy-sequence features)))
        (flycheck-mode nil))
    (should-not (p3/appearance--flycheck-segment))))

(ert-deftest p3-appearance-coding-segment-distinguishes-eol ()
  (with-temp-buffer
    (setq buffer-file-coding-system 'utf-8-unix)
    (should (equal "UTF-8 LF" (p3/appearance--coding-segment)))
    (setq buffer-file-coding-system 'utf-8-dos)
    (should (equal "UTF-8 CRLF" (p3/appearance--coding-segment)))))
```

- [ ] **Step 2: Add exact RED redisplay guards**

Add:

```elisp
(ert-deftest p3-appearance-render-does-not-discover-project-or-run-processes ()
  (with-temp-buffer
    (setq buffer-file-name "/tmp/example.R"
          p3/appearance--icons-available nil)
    (cl-letf (((symbol-function 'project-current)
               (lambda (&rest _)
                 (ert-fail "project-current during redisplay")))
              ((symbol-function 'process-file)
               (lambda (&rest _)
                 (ert-fail "process-file during redisplay"))))
      (should (stringp
               (format-mode-line (default-value 'mode-line-format)))))))

(ert-deftest p3-appearance-remote-render-does-not-touch-filesystem ()
  (with-temp-buffer
    (setq buffer-file-name "/ssh:example.org:/tmp/example.R"
          default-directory "/ssh:example.org:/tmp/"
          p3/appearance--icons-available nil)
    (cl-letf (((symbol-function 'file-exists-p)
               (lambda (&rest _) (ert-fail "file-exists-p during redisplay")))
              ((symbol-function 'file-attributes)
               (lambda (&rest _) (ert-fail "file-attributes during redisplay")))
              ((symbol-function 'directory-files)
               (lambda (&rest _) (ert-fail "directory-files during redisplay"))))
      (should (stringp
               (format-mode-line (default-value 'mode-line-format)))))))

(ert-deftest p3-appearance-no-font-path-does-not-call-nerd-renderers ()
  (with-temp-buffer
    (setq buffer-file-name "/tmp/example.R"
          p3/appearance--icons-available nil)
    (cl-letf (((symbol-function 'nerd-icons-icon-for-file)
               (lambda (&rest _) (ert-fail "file icon called")))
              ((symbol-function 'nerd-icons-icon-for-buffer)
               (lambda (&rest _) (ert-fail "buffer icon called")))
              ((symbol-function 'nerd-icons-icon-for-mode)
               (lambda (&rest _) (ert-fail "mode icon called")))
              ((symbol-function 'nerd-icons-octicon)
               (lambda (&rest _) (ert-fail "git icon called")))
              ((symbol-function 'nerd-icons-codicon)
               (lambda (&rest _) (ert-fail "remote icon called"))))
      (should (stringp
               (format-mode-line (default-value 'mode-line-format)))))))
```

Run focused ERT. Expected: FAIL because status/coding functions do not exist.

- [ ] **Step 3: Implement bounded VC and Flycheck state**

Append before `provide`:

```elisp
(defun p3/appearance--git-icon ()
  (or (p3/appearance--safe-icon
       #'nerd-icons-octicon "nf-oct-git_branch" :height 0.95)
      "Git"))

(defun p3/appearance--vc-text ()
  (when vc-mode
    (truncate-string-to-width
     (string-trim (format-mode-line vc-mode)) 12 nil nil "…")))

(defun p3/appearance--vc-segment ()
  (when-let ((text (p3/appearance--vc-text)))
    (p3/appearance--join (p3/appearance--git-icon) text)))

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
      (p3/appearance--join
       (when (> errors 0)
         (propertize (format "×%d" errors) 'face 'error))
       (when (> warnings 0)
         (propertize (format "!%d" warnings) 'face 'warning))
       (when (> infos 0) (format "i%d" infos)))))))

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

- [ ] **Step 4: Implement coding and narrow-width right side**

Append:

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
    (p3/appearance--join vc flycheck coding position)))
```

The existing file label drops project path detail below 120 columns, and left-side process text disappears below 100 columns. Position, filename, remote host, and mode identity remain.

- [ ] **Step 5: Run GREEN and commit**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-appearance-test.el \
  -f ert-run-tests-batch-and-exit
```

Expected: PASS including redisplay guards.

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
- Produces: reload idempotency regression, strict compile coverage, batch smoke load, full ERT inclusion.

- [ ] **Step 1: Add exact reload/idempotency regression**

Add:

```elisp
(ert-deftest p3-appearance-reload-is-idempotent ()
  (let ((p3/appearance--icons-available nil))
    (p3-config-appearance-test--load-appearance)
    (p3-config-appearance-test--load-appearance)
    (should (= 1 (cl-count #'p3/appearance-refresh-buffer-context
                           find-file-hook :test #'eq)))
    (should (= 1 (cl-count #'p3/appearance-refresh-buffer-context
                           after-change-major-mode-hook :test #'eq)))
    (should-not (memq #'nerd-icons-dired-mode dired-mode-hook))
    (should (equal (default-value 'mode-line-format)
                   (p3/appearance--build-mode-line-format)))
    (setq p3/appearance--icons-available t)
    (p3/appearance-sync-dired-icons)
    (p3/appearance-sync-dired-icons)
    (should (= 1 (cl-count #'nerd-icons-dired-mode
                           dired-mode-hook :test #'eq)))))
```

Run focused Appearance ERT. Expected: PASS.

- [ ] **Step 2: Extend Ubuntu compile/smoke/ERT coverage**

In `.github/workflows/emacs-tests.yml`:

- add `lisp/p3-config-appearance.el` to warnings-as-errors compilation;
- add `-l test/p3-config-appearance-test.el` to full ERT;
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

Expected: exit 0 under `emacs-nox` with no Nerd Font.

- [ ] **Step 3: Extend Windows source/compile/test coverage**

In `.github/workflows/windows-platform-tests.yml`:

- add `lisp/p3-config-appearance.el` and `test/p3-config-appearance-test.el` to `pull_request.paths`;
- add `lisp/p3-config-appearance.el` to strict Windows byte compilation;
- add `-l test/p3-config-appearance-test.el` to Windows config architecture tests.

Do not add graphical Windows CI.

- [ ] **Step 4: Run available local/static gates and commit**

Run focused ERT. If local Emacs exists, run the full ERT command from `.github/workflows/emacs-tests.yml`.

Run:

```bash
git grep -n -E '\(use-package (doom-modeline|all-the-icons|all-the-icons-dired|unicode-fonts)' -- . ':!docs/superpowers/**'
```

Expected: no active-source matches.

Commit:

```bash
git add .github/workflows/emacs-tests.yml \
  .github/workflows/windows-platform-tests.yml \
  test/p3-config-appearance-test.el
git commit -m "Harden appearance configuration checks"
```

---

### Task 6: Open draft PR and verify exact automated head

**Files:**
- No source modification unless verification finds a defect.

**Interfaces:**
- Produces: draft PR, exact-head Ubuntu/Windows evidence, remaining manual graphical acceptance requirement.

- [ ] **Step 1: Open a draft PR**

Use `refactor/appearance-config`. Body must state legacy package removal, native mode-line information contract, remote/VC/Flycheck/coding behavior, redisplay constraints, Nerd Font fallback, unchanged theme, and pending graphical acceptance.

- [ ] **Step 2: Verify exact-head Ubuntu**

Require PASS for strict Appearance compile, Appearance smoke, existing subsystem smokes, and full ERT including Appearance tests. On failure, retrieve the exact failing job log, fix root cause, run the narrow gate, then rerun the final full gate.

- [ ] **Step 3: Verify exact-head Windows**

Require PASS on the same SHA for strict Appearance compilation and config architecture tests including Appearance, plus existing native Windows gates.

- [ ] **Step 4: Adversarial final automated diff check**

Verify no config-module coupling; no project discovery/subprocess/file/remote I/O/package load/VC refresh in mode-line eval paths; no automatic font download; no theme or coding-policy drift; no generalized cache/timer/framework; Dashboard/Dired behavior remains Base-owned while icon presentation is Appearance-owned; old package declarations are absent.

Do not mark merge-ready.

---

### Task 7: Perform graphical acceptance and minimal visual tuning

**Files:**
- Modify only `lisp/p3-config-appearance.el` for evidence-driven spacing/threshold/face/glyph tuning.
- Modify tests only if behavior contract changes.

**Interfaces:**
- Produces: human-verified graphical appearance and final reviewed SHA.

- [ ] **Step 1: Verify missing-font fallback**

With `Symbols Nerd Font Mono` unavailable, verify graphical Emacs shows readable text/Unicode mode line, Dashboard/Dired without tofu, and no startup font installation.

- [ ] **Step 2: Install font explicitly and reload**

```text
M-x nerd-icons-install-fonts
```

Restart only if the platform requires font rediscovery; otherwise `C-c r`. Verify file and major-mode icons plus Dashboard/Dired Nerd Icons.

- [ ] **Step 3: Exercise all graphical cases**

Check:

1. local project file on Git branch;
2. modified file;
3. read-only buffer;
4. Flycheck running and finished-with-diagnostics;
5. meaningful `mode-line-process` buffer;
6. narrow window;
7. remote/TRAMP buffer when endpoint exists;
8. Dashboard;
9. Dired;
10. active vs inactive windows;
11. text buffer containing `— → ✓ λ ∑`;
12. repeated `C-c r`.

No noticeable typing/scrolling/redisplay lag locally or due to remote rendering.

- [ ] **Step 4: Tune only permitted visual parameters**

Permitted: spacing, relative mode-line height/weight/box attributes, theme-derived active/inactive contrast, width thresholds `120/100/80`, VC bound near 12 columns, individual Nerd glyph choice. Forbidden: new segments/packages/timers/generalized caches/literal palette colors.

- [ ] **Step 5: Re-run gates after any tuning**

```bash
emacs -Q --batch -L lisp \
  -l test/p3-config-appearance-test.el \
  -f ert-run-tests-batch-and-exit
```

Then require fresh exact-head Ubuntu and Windows PR gates.

- [ ] **Step 6: Final adversarial review and stop before merge**

Confirm approved spec compliance, exact-head automated green status, completed graphical matrix, final SHA, and any remaining caveat. Do not merge without explicit approval.
