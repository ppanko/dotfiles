;;; p3-config-appearance-test.el --- Appearance configuration tests -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'ert)
(require 'subr-x)

(defvar features)
(defvar flycheck-mode)
(defvar flycheck-last-status-change)
(defvar flycheck-current-errors)
(defvar vc-mode)

(defconst p3-config-appearance-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(defun p3-config-appearance-test--contents (relative)
  "Return contents of RELATIVE under the repository root."
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name relative p3-config-appearance-test--root))
    (buffer-string)))

(defun p3-config-appearance-test--count (needle contents)
  "Count non-overlapping NEEDLE occurrences in CONTENTS."
  (let ((start 0)
        (count 0)
        (regexp (regexp-quote needle)))
    (while (string-match regexp contents start)
      (setq count (1+ count)
            start (match-end 0)))
    count))

(defun p3-config-appearance-test--load-appearance ()
  "Load the real appearance module with external packages stubbed."
  (require 'use-package-ensure)
  (setq use-package-ensure-function (lambda (&rest _) t))
  (defvar nerd-icons-font-family "Symbols Nerd Font Mono")
  (unless (fboundp 'nerd-icons-icon-for-file)
    (defalias 'nerd-icons-icon-for-file (lambda (&rest _) "F")))
  (unless (fboundp 'nerd-icons-icon-for-buffer)
    (defalias 'nerd-icons-icon-for-buffer (lambda (&rest _) "B")))
  (unless (fboundp 'nerd-icons-icon-for-mode)
    (defalias 'nerd-icons-icon-for-mode (lambda (&rest _) "M")))
  (unless (fboundp 'nerd-icons-octicon)
    (defalias 'nerd-icons-octicon (lambda (&rest _) "G")))
  (unless (fboundp 'nerd-icons-codicon)
    (defalias 'nerd-icons-codicon (lambda (&rest _) "R")))
  (provide 'nerd-icons)
  (provide 'doom-themes)
  (cl-letf (((symbol-function 'load-theme) (lambda (&rest _) t))
            ((symbol-function 'display-graphic-p) (lambda (&optional _) nil)))
    (load-file
     (expand-file-name "lisp/p3-config-appearance.el"
                       p3-config-appearance-test--root))))

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
                       "dashboard-icon-type"
                       "nerd-icons-dired-mode"))
      (should (string-match-p (regexp-quote needle) appearance)))
    (dolist (forbidden '("(use-package doom-modeline"
                          "(use-package all-the-icons"
                          "(use-package all-the-icons-dired"
                          "(use-package unicode-fonts"))
      (should-not (string-match-p (regexp-quote forbidden) appearance))
      (should-not (string-match-p (regexp-quote forbidden) base))
      (should-not (string-match-p (regexp-quote forbidden) config)))
    (should-not (string-match-p "dashboard-icon-type" base))
    (should (string-match-p "initial-scratch-message" base))
    (should (string-match-p "ring-bell-function" base))
    (should (string-match-p "default-process-coding-system" config))
    (should (string-match-p "\\\\.Rmd" config))))

(ert-deftest p3-config-appearance-does-not-couple-config-modules ()
  (let ((appearance
         (p3-config-appearance-test--contents "lisp/p3-config-appearance.el")))
    (should-not
     (string-match-p
      "\\(?:require\\|p3/config-load-module\\).*p3-config-"
      appearance))))

(ert-deftest p3-appearance-file-segment-keeps-text-without-icons ()
  (p3-config-appearance-test--load-appearance)
  (with-temp-buffer
    (setq buffer-file-name "/tmp/project/src/example.R"
          p3/appearance--icons-available nil
          p3/appearance--project-relative-file "src/example.R")
    (cl-letf (((symbol-function 'window-total-width) (lambda (&optional _) 140)))
      (should (string-match-p "src/example\\.R"
                              (p3/appearance--file-segment))))))

(ert-deftest p3-appearance-remote-host-is-textual ()
  (p3-config-appearance-test--load-appearance)
  (with-temp-buffer
    (setq buffer-file-name "/ssh:example.org:/tmp/example.R")
    (should (equal "example.org" (p3/appearance--remote-host)))))

(ert-deftest p3-appearance-mode-segment-keeps-mode-name-without-icons ()
  (p3-config-appearance-test--load-appearance)
  (with-temp-buffer
    (emacs-lisp-mode)
    (let ((p3/appearance--icons-available nil))
      (should (string-match-p "Emacs-Lisp"
                              (p3/appearance--mode-segment))))))

(ert-deftest p3-appearance-selects-native-and-fallback-alignment ()
  (p3-config-appearance-test--load-appearance)
  (cl-letf (((symbol-function 'p3/appearance--native-right-align-p)
             (lambda () t)))
    (should (memq 'mode-line-format-right-align
                  (p3/appearance--build-mode-line-format))))
  (cl-letf (((symbol-function 'p3/appearance--native-right-align-p)
             (lambda () nil)))
    (should-not (memq 'mode-line-format-right-align
                      (p3/appearance--build-mode-line-format)))))

(ert-deftest p3-appearance-vc-segment-is-bounded ()
  (p3-config-appearance-test--load-appearance)
  (with-temp-buffer
    (let ((vc-mode " Git:feature/an-excessively-long-branch-name")
          (p3/appearance--icons-available nil))
      (should (<= (string-width (p3/appearance--vc-segment)) 16)))))

(ert-deftest p3-appearance-flycheck-state-mapping-is-explicit ()
  (p3-config-appearance-test--load-appearance)
  (let ((features (cons 'flycheck features))
        (flycheck-mode t)
        (flycheck-current-errors '(fake)))
    (cl-letf (((symbol-function 'flycheck-count-errors)
               (lambda (_errors)
                 '((error . 2) (warning . 1) (info . 1)))))
      (let ((flycheck-last-status-change 'running))
        (should (stringp (p3/appearance--flycheck-segment))))
      (let ((flycheck-last-status-change 'finished))
        (let ((text (p3/appearance--flycheck-segment)))
          (should (string-match-p "2" text))
          (should (string-match-p "1" text))))
      (dolist (state '(errored suspicious interrupted))
        (let ((flycheck-last-status-change state))
          (should (stringp (p3/appearance--flycheck-segment)))))
      (dolist (state '(no-checker not-checked))
        (let ((flycheck-last-status-change state))
          (should-not (p3/appearance--flycheck-segment)))))))

(ert-deftest p3-appearance-coding-segment-is-concise ()
  (p3-config-appearance-test--load-appearance)
  (with-temp-buffer
    (setq buffer-file-coding-system 'utf-8-unix)
    (should (equal "UTF-8 LF" (p3/appearance--coding-segment)))
    (setq buffer-file-coding-system 'utf-8-dos)
    (should (equal "UTF-8 CRLF" (p3/appearance--coding-segment)))))

(ert-deftest p3-appearance-rendering-avoids-expensive-work ()
  (p3-config-appearance-test--load-appearance)
  (with-temp-buffer
    (setq buffer-file-name "/ssh:example.org:/tmp/example.R"
          p3/appearance--icons-available nil)
    (cl-letf (((symbol-function 'project-current)
               (lambda (&rest _) (ert-fail "project-current during redisplay")))
              ((symbol-function 'process-file)
               (lambda (&rest _) (ert-fail "process-file during redisplay")))
              ((symbol-function 'file-exists-p)
               (lambda (&rest _) (ert-fail "file-exists-p during redisplay")))
              ((symbol-function 'file-attributes)
               (lambda (&rest _) (ert-fail "file-attributes during redisplay")))
              ((symbol-function 'directory-files)
               (lambda (&rest _) (ert-fail "directory-files during redisplay")))
              ((symbol-function 'nerd-icons-icon-for-file)
               (lambda (&rest _) (ert-fail "icon rendering with icons disabled")))
              ((symbol-function 'nerd-icons-icon-for-mode)
               (lambda (&rest _) (ert-fail "icon rendering with icons disabled")))
              ((symbol-function 'window-total-width) (lambda (&optional _) 140)))
      (should (stringp (p3/appearance--left-segment)))
      (should (stringp (p3/appearance--right-segment))))))

(ert-deftest p3-appearance-reload-is-idempotent ()
  (p3-config-appearance-test--load-appearance)
  (p3-config-appearance-test--load-appearance)
  (should (= 1 (cl-count #'p3/appearance-refresh-buffer-context
                         find-file-hook :test #'eq)))
  (should (= 1 (cl-count #'p3/appearance-refresh-buffer-context
                         after-change-major-mode-hook :test #'eq)))
  (should (= 1 (cl-count #'p3/appearance-apply-frame-font
                         after-make-frame-functions :test #'eq)))
  (should (= 1 (cl-count #'p3/appearance--configure-dashboard-after-load
                         after-load-functions :test #'eq)))
  (should-not (memq #'nerd-icons-dired-mode dired-mode-hook))
  (should (equal (default-value 'mode-line-format)
                 (p3/appearance--build-mode-line-format)))
  (let ((p3/appearance--icons-available t))
    (p3/appearance-sync-dired-icons)
    (p3/appearance-sync-dired-icons)
    (should (= 1 (cl-count #'nerd-icons-dired-mode
                           dired-mode-hook :test #'eq)))))

(provide 'p3-config-appearance-test)

;;; p3-config-appearance-test.el ends here
