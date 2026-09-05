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
(defvar vc-mode)
(defvar doom-modeline-mode)
(defvar mode-line-right-align-edge)

(declare-function nerd-icons-icon-for-file "nerd-icons" (file &rest args))
(declare-function nerd-icons-icon-for-buffer "nerd-icons" (&rest args))
(declare-function nerd-icons-icon-for-mode "nerd-icons" (mode &rest args))
(declare-function nerd-icons-octicon "nerd-icons" (name &rest args))
(declare-function nerd-icons-codicon "nerd-icons" (name &rest args))
(declare-function nerd-icons-dired-mode "nerd-icons-dired" (&optional arg))
(declare-function all-the-icons-dired-mode "all-the-icons-dired" (&optional arg))
(declare-function flycheck-count-errors "flycheck" (errors))
(declare-function doom-modeline-mode "doom-modeline" (&optional arg))

(defvar p3/appearance--icons-available nil
  "Non-nil when Nerd Font icons are safe to render.")

(defvar-local p3/appearance--project-root nil
  "Cached local project root used only for presentation.")

(defvar-local p3/appearance--project-relative-file nil
  "Cached project-relative file name used only for presentation.")

(defun p3/appearance-refresh-icon-availability ()
  "Refresh whether Nerd Font icons are safe to render."
  (setq p3/appearance--icons-available
        (and (display-graphic-p)
             (find-font
              (font-spec :family
                         (or (and (boundp 'nerd-icons-font-family)
                                  nerd-icons-font-family)
                             "Symbols Nerd Font Mono"))))))

(defun p3/appearance-apply-frame-font (&optional frame)
  "Apply the platform default font to graphical FRAME."
  (when (display-graphic-p frame)
    (with-selected-frame (or frame (selected-frame))
      (cond
       ((eq system-type 'windows-nt)
        (set-face-attribute 'default nil :family "Consolas" :height 125))
       ((eq system-type 'gnu/linux)
        (set-face-attribute 'default nil :family "Inconsolata" :height 140))))))

(add-to-list 'default-frame-alist '(fullscreen . maximized))
(add-hook 'after-make-frame-functions #'p3/appearance-apply-frame-font)
(p3/appearance-apply-frame-font)

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

(set-face-attribute 'mode-line nil :box nil :weight 'semi-bold :height 1.05)
(set-face-attribute 'mode-line-inactive nil :box nil :weight 'normal)
(set-face-attribute 'line-number-current-line nil :weight 'bold)

;; Retire the old modeline when this source is reloaded into an existing
;; session. This does not load or configure doom-modeline.
(when (and (fboundp 'doom-modeline-mode)
           (bound-and-true-p doom-modeline-mode))
  (doom-modeline-mode -1))

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

(defun p3/appearance--configure-dashboard-after-load (&rest _)
  "Apply Dashboard appearance once Dashboard becomes available."
  (when (featurep 'dashboard)
    (p3/appearance-configure-dashboard-icons)
    (remove-hook 'after-load-functions
                 #'p3/appearance--configure-dashboard-after-load)))

(remove-hook 'after-load-functions #'p3/appearance--configure-dashboard-after-load)
(if (featurep 'dashboard)
    (p3/appearance-configure-dashboard-icons)
  (add-hook 'after-load-functions #'p3/appearance--configure-dashboard-after-load))

(use-package nerd-icons-dired
  :commands nerd-icons-dired-mode)

(defun p3/appearance-sync-dired-icons ()
  "Reconcile the Dired icon hook with current font availability."
  (remove-hook 'dired-mode-hook #'all-the-icons-dired-mode)
  (remove-hook 'dired-mode-hook #'nerd-icons-dired-mode)
  (when p3/appearance--icons-available
    (add-hook 'dired-mode-hook #'nerd-icons-dired-mode)))

(p3/appearance-sync-dired-icons)

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

(dolist (buffer (buffer-list))
  (with-current-buffer buffer
    (when buffer-file-name
      (p3/appearance-refresh-buffer-context))))

(defun p3/appearance--join (&rest parts)
  "Join nonempty string PARTS with restrained spacing."
  (string-join
   (cl-remove-if (lambda (part)
                   (or (null part)
                       (and (stringp part) (string-empty-p part))))
                 parts)
   "  "))

(defun p3/appearance--safe-icon (function &rest args)
  "Call icon FUNCTION with ARGS when icons are available, or return nil."
  (when p3/appearance--icons-available
    (condition-case nil
        (apply function args)
      (error nil))))

(defun p3/appearance--format-construct (construct)
  "Format mode-line CONSTRUCT using the current buffer's state."
  (cond
   ((null construct) "")
   ((stringp construct) construct)
   (t (format-mode-line construct nil nil (current-buffer)))))

(defun p3/appearance--remote-host ()
  "Return the current buffer's remote host without remote I/O."
  (file-remote-p (or buffer-file-name default-directory) 'host))

(defun p3/appearance--buffer-state ()
  "Return compact modified/read-only buffer state text."
  (cond
   (buffer-read-only (propertize "RO" 'face 'shadow))
   ((buffer-modified-p) (propertize "●" 'face 'warning))
   (t nil)))

(defun p3/appearance--file-label ()
  "Return a concise file or buffer identity label."
  (cond
   ((not buffer-file-name) (buffer-name))
   ((file-remote-p buffer-file-name)
    (file-name-nondirectory buffer-file-name))
   ((and (>= (window-total-width) 120)
         p3/appearance--project-relative-file)
    p3/appearance--project-relative-file)
   (t (file-name-nondirectory buffer-file-name))))

(defun p3/appearance--file-segment ()
  "Return file/buffer identity with an optional icon and mandatory text."
  (let* ((label (p3/appearance--file-label))
         (icon (if buffer-file-name
                   (p3/appearance--safe-icon
                    #'nerd-icons-icon-for-file buffer-file-name :height 0.95)
                 (p3/appearance--safe-icon
                  #'nerd-icons-icon-for-buffer :height 0.95))))
    (if icon (format "%s %s" icon label) label)))

(defun p3/appearance--remote-segment ()
  "Return textual remote host identity with an optional icon."
  (when-let ((host (p3/appearance--remote-host)))
    (let ((icon (p3/appearance--safe-icon
                 #'nerd-icons-codicon "nf-cod-remote" :height 0.95)))
      (if icon (format "%s %s" icon host) host))))

(defun p3/appearance--mode-segment ()
  "Return major-mode identity with an optional icon and mandatory text."
  (let* ((text (or (p3/appearance--format-construct mode-name)
                   (symbol-name major-mode)))
         (text (if (string-empty-p text) (symbol-name major-mode) text))
         (icon (p3/appearance--safe-icon
                #'nerd-icons-icon-for-mode major-mode :height 0.95)))
    (if icon (format "%s %s" icon text) text)))

(defun p3/appearance--process-segment ()
  "Return existing mode-provided process state on sufficiently wide windows."
  (when (and (>= (window-total-width) 100) mode-line-process)
    (let ((text (string-trim
                 (p3/appearance--format-construct mode-line-process))))
      (unless (string-empty-p text) text))))

(defun p3/appearance--left-segment ()
  "Return the left identity area of the mode line."
  (p3/appearance--join
   (p3/appearance--buffer-state)
   (p3/appearance--remote-segment)
   (p3/appearance--file-segment)
   (p3/appearance--mode-segment)
   (p3/appearance--process-segment)))

(defun p3/appearance--git-icon ()
  "Return a Git/branch icon or text fallback."
  (or (p3/appearance--safe-icon
       #'nerd-icons-octicon "nf-oct-git_branch" :height 0.95)
      "Git"))

(defun p3/appearance--vc-segment ()
  "Return bounded presentation of existing VC state."
  (when vc-mode
    (let* ((raw (string-trim (p3/appearance--format-construct vc-mode)))
           (text (truncate-string-to-width raw 12 nil nil "…")))
      (format "%s %s" (p3/appearance--git-icon) text))))

(defun p3/appearance--flycheck-finished-segment (&optional compact)
  "Return finished Flycheck state, reducing detail when COMPACT is non-nil."
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
  "Return existing Flycheck state without triggering a check.
When COMPACT is non-nil, show only the most important finished count."
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

(defun p3/appearance--coding-segment ()
  "Return concise encoding and EOL information for the current buffer."
  (let* ((coding buffer-file-coding-system)
         (base (or (coding-system-base coding) coding 'undecided))
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

(defun p3/appearance--position-segment ()
  "Return current line and column."
  (format-mode-line "%l:%c"))

(defun p3/appearance--right-segment ()
  "Return the right status area of the mode line."
  (let* ((width (window-total-width))
         (vc (p3/appearance--vc-segment))
         (flycheck (p3/appearance--flycheck-segment (< width 80)))
         (coding (and (>= width 100) (p3/appearance--coding-segment)))
         (position (p3/appearance--position-segment)))
    (p3/appearance--join vc flycheck coding position)))

(defun p3/appearance--native-right-align-p ()
  "Return non-nil when native mode-line right alignment is available."
  (boundp 'mode-line-format-right-align))

(defun p3/appearance--right-align-space ()
  "Return the Emacs 29 display-space right-alignment fallback."
  (let ((width (string-width (p3/appearance--right-segment))))
    (propertize " " 'display
                `((space :align-to (- right ,(+ width 1)))))))

(defun p3/appearance--build-mode-line-format ()
  "Build the P3 default mode-line format."
  (append
   '("%e " (:eval (p3/appearance--left-segment)))
   (if (p3/appearance--native-right-align-p)
       '(mode-line-format-right-align)
     '((:eval (p3/appearance--right-align-space))))
   '((:eval (p3/appearance--right-segment)) " ")))

(setq-default mode-line-format (p3/appearance--build-mode-line-format))
(when (boundp 'mode-line-right-align-edge)
  (setq-default mode-line-right-align-edge 'window))

(provide 'p3-config-appearance)

;;; p3-config-appearance.el ends here
