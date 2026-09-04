;;; p3-config-base.el --- Broad global configuration -*- lexical-binding: t; -*-

(require 'use-package)
(require 'p3-config-loader)
(p3/config-load-module 'p3-commands)

(defvar dashboard-startup-banner)
(defvar dashboard-center-content)
(defvar dashboard-icon-type)
(defvar dashboard-path-style)
(defvar dashboard-path-max-length)
(defvar dashboard-projects-show-base)
(defvar dashboard-recentf-show-base)
(defvar dashboard-recentf-item-format)
(defvar dashboard-projects-item-format)
(defvar dashboard-items)
(defvar p3/package-refresh-attempted)
(defvar comint-scroll-to-bottom-on-input)
(defvar comint-scroll-to-bottom-on-output)
(defvar mouse-wheel-scroll-amount)
(defvar mouse-wheel-progressive-speed)
(defvar tramp-backup-directory-alist)
(defvar tramp-auto-save-directory)
(defvar all-the-icons-scale-factor)

(declare-function dashboard-setup-startup-hook "dashboard" ())
(declare-function which-key-mode "which-key" (&optional arg))
(declare-function which-key-add-key-based-replacements "which-key" (&rest replacements))
(declare-function dired-async-mode "dired-async" (&optional arg))
(declare-function async-bytecomp-package-mode "async-bytecomp" (&optional arg))
(declare-function all-the-icons-install-fonts "all-the-icons" (&optional pfx))
(declare-function package-refresh-contents "package" (&optional async))
(declare-function package-list-packages "package" (&optional no-fetch))

(add-to-list 'default-frame-alist '(fullscreen . maximized))

(use-package dashboard
  :config
  (dashboard-setup-startup-hook)
  (setq dashboard-startup-banner 'official
        dashboard-center-content t
        dashboard-icon-type 'all-the-icons
        dashboard-path-style 'truncate-end
        dashboard-path-max-length 60
        dashboard-projects-show-base 'align
        dashboard-recentf-show-base 'align
        dashboard-recentf-item-format "%s  %s"
        dashboard-projects-item-format "%s  %s"
        dashboard-items '((recents . 10))))

(use-package which-key
  :diminish which-key-mode
  :init
  (which-key-mode 1)
  :custom
  (which-key-idle-delay 0.5)
  (which-key-sort-order 'which-key-key-order-alpha)
  :bind ("C-c ?" . p3/keybinding-atlas)
  :config
  (which-key-add-key-based-replacements
   "C-c ?" "show keybindings"
   "C-c a" "align region"
   "C-c e" "visit config"
   "C-c E" "export Org file"
   "C-c g" "GPTel tasks"
   "C-c h" "R documentation search"
   "C-c k" "kill buffer and window"
   "C-c m" "Magit commands"
   "C-c n" "Org-roam"
   "C-c q" "force quotes"
   "C-c r" "reload config"
   "C-c R" "R commands"
   "C-c s" "region suffix"
   "C-c t" "transpose frame"
   "C-c C-g" "commit and push config"
   "C-c C-SPC" "insert newline after comma"
   "C-c g l" "send current line"
   "C-c g r" "refactor region"
   "C-c g d" "generate documentation"
   "C-c g t" "write tests"
   "C-c g c" "translate code"
   "C-c g w" "write code"
   "C-c m s" "stage files"
   "C-c m c" "commit"
   "C-c m f" "pull"
   "C-c m m" "merge"
   "C-c m P" "push"
   "C-c m a" "add remote"
   "C-c m g" "status"
   "C-c m l" "log"
   "C-c m d" "diff"
   "C-c m b" "blame"
   "C-c m q" "close Magit buffers"
   "C-c n l" "Org-roam buffer"
   "C-c n f" "find node"
   "C-c n g" "graph"
   "C-c n i" "insert node"
   "C-c n c" "capture node"
   "C-c R p" "new R project"
   "C-c R h" "R script header"
   "C-c R w" "Word report header"
   "C-c R c" "insert R chunk"
   "C-c R i" "insert pipe"
   "C-c R m" "targets make"
   "C-c R v" "view data frame"))

(use-package package
  :ensure nil
  :commands package-upgrade-all)

(defun p3/package-update ()
  "Open the package menu to review and selectively apply upgrades."
  (interactive)
  (package-refresh-contents)
  (setq p3/package-refresh-attempted t)
  (package-list-packages t)
  (message "Review upgrades with U, then execute selected actions with x."))

(when (eq system-type 'windows-nt)
  (set-face-attribute 'default nil :family "Consolas" :height 125))
(when (eq system-type 'gnu/linux)
  (set-face-attribute 'default nil :family "Inconsolata" :height 140))

(setq-default cursor-type 'bar)

(fset 'yes-or-no-p 'y-or-n-p)

(defun y-or-n-p-with-return (orig-func &rest args)
  (let ((query-replace-map (copy-keymap query-replace-map)))
    (define-key query-replace-map (kbd "<return>") 'act)
    (apply orig-func args)))

(advice-add 'y-or-n-p :around #'y-or-n-p-with-return)

(defun p3/process-kill-query (process)
  "Ask using `y-or-n-p` whether to kill PROCESS."
  (y-or-n-p (format "Kill process %s? " (process-name process))))

(setq kill-buffer-query-functions
      (remq 'process-kill-buffer-query-function
            kill-buffer-query-functions))

(add-hook 'kill-buffer-query-functions
          (lambda ()
            (if (get-buffer-process (current-buffer))
                (p3/process-kill-query (get-buffer-process (current-buffer)))
              t)))

(setq comint-scroll-to-bottom-on-input t)
(setq comint-scroll-to-bottom-on-output t)

(setq scroll-conservatively 1)
(setq mouse-wheel-scroll-amount '(5))
(setq mouse-wheel-progressive-speed nil)

(setq delete-by-moving-to-trash t)

(use-package async
  :init
  (dired-async-mode 1)
  (async-bytecomp-package-mode 1))

(global-font-lock-mode t)
(global-auto-revert-mode t)

(defun p3/set-line-numbers ()
  (interactive)
  (column-number-mode)
  (dolist (mode '(text-mode-hook
                  prog-mode-hook
                  conf-mode-hook))
    (add-hook mode (lambda ()
                     (display-line-numbers-mode 1)
                     (set-face-foreground 'line-number-current-line "#FFD700")))))

(p3/set-line-numbers)

(global-set-key (kbd "<C-wheel-down>") 'text-scale-decrease)
(global-set-key (kbd "<C-wheel-up>") 'text-scale-increase)

(let ((backup-dir "~/.cache/tmp/emacs/backups")
      (auto-saves-dir "~/.cache/tmp/emacs/auto-saves/"))
  (dolist (dir (list backup-dir auto-saves-dir))
    (when (not (file-directory-p dir))
      (make-directory dir t)))
  (setq backup-directory-alist `(("." . ,backup-dir))
        auto-save-file-name-transforms `((".*" ,auto-saves-dir t))
        tramp-backup-directory-alist `((".*" . ,backup-dir))
        tramp-auto-save-directory auto-saves-dir))

(setq backup-by-copying t
      delete-old-versions t
      version-control t
      kept-new-versions 5
      kept-old-versions 2)

(use-package dired
  :ensure nil
  :after all-the-icons-dired
  :hook (dired-mode . all-the-icons-dired-mode)
  :custom
  (dired-auto-revert-buffer t)
  (dired-kill-when-opening-new-dired-buffer t))

(use-package all-the-icons
  :if (display-graphic-p)
  :config
  (unless (find-font (font-spec :name "all-the-icons"))
    (all-the-icons-install-fonts t))
  (setq all-the-icons-scale-factor 1))

(use-package all-the-icons-dired
  :after all-the-icons)

(when (eq system-type 'windows-nt)
  (global-set-key (kbd "C-x C-i") #'p3/windows-shell))

(provide 'p3-config-base)

;;; p3-config-base.el ends here
