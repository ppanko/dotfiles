;;; p3-config-test.el --- Smoke tests for the Emacs config -*- lexical-binding: t; -*-

(require 'ert)

(defconst p3-config-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-config-test--root))
(require 'p3-config-loader)

(defun p3-config-test--assert-readable-elisp (path)
  "Fail when PATH does not contain syntactically readable Emacs Lisp."
  (with-temp-buffer
    (insert-file-contents path)
    (emacs-lisp-mode)
    (condition-case err
        (progn
          (check-parens)
          (goto-char (point-min))
          (condition-case nil
              (while t
                (read (current-buffer)))
            (end-of-file t)))
      (error
       (ert-fail
        (format "Could not read %s: %s" path (error-message-string err)))))))

(ert-deftest p3-init-el-is-readable ()
  (p3-config-test--assert-readable-elisp
   (expand-file-name "init.el" p3-config-test--root)))

(ert-deftest p3-config-org-builds-through-production-cache-contract ()
  (let* ((directory (make-temp-file "p3-config-real-build-" t))
         (p3/config-source
          (expand-file-name "config.org" p3-config-test--root))
         (p3/config-generated
          (expand-file-name "config.el" directory)))
    (unwind-protect
        (progn
          (should (equal (p3/config-build) p3/config-generated))
          (should-not (p3/config-cache-stale-p))
          (with-temp-buffer
            (insert-file-contents p3/config-generated)
            (goto-char (point-min))
            (should
             (looking-at
              ";; p3-config-source-sha256: [0-9a-f]\\{64\\}$")))
          (p3-config-test--assert-readable-elisp p3/config-generated))
      (delete-directory directory t))))

(ert-deftest p3-config-org-owns-org-export-integration ()
  (with-temp-buffer
    (insert-file-contents (expand-file-name "config.org" p3-config-test--root))
    (should (search-forward "(use-package p3-org-export" nil t))
    (goto-char (point-min))
    (should-not (search-forward "(defun p3/org-export-to-office" nil t))
    (goto-char (point-min))
    (should (search-forward "(\"C-c C-o\" . \"open link at point\")" nil t))
    (goto-char (point-min))
    (should (search-forward "(\"C-c E\" . \"export Org file\")" nil t))))

(ert-deftest p3-config-org-delegates-custom-subsystems-to-modules ()
  (with-temp-buffer
    (insert-file-contents (expand-file-name "config.org" p3-config-test--root))
    (dolist (module '("p3-platform" "p3-core" "p3-python" "p3-terminal"
                      "p3-ess" "p3-gptel"))
      (goto-char (point-min))
      (should (search-forward (format "(use-package %s" module) nil t)))
    (dolist (package '("python" "eglot" "ess-r-mode" "vterm" "gptel"))
      (goto-char (point-min))
      (should (search-forward (format "(use-package %s" package) nil t)))
    (dolist (implementation '("(defun p3/windows-rtools-version"
                               "(defun p3/windows-latest-r-program"
                               "(defun p3/project-root"
                               "(defun p3/python-project-interpreter"
                               "(defun p3/vterm-buffer"
                               "(defun p3/ess-project-root"
                               "(defun p3/ess-ensure-project-process"
                               "(defun p3/gptel-send-task"))
      (goto-char (point-min))
      (should-not (search-forward implementation nil t)))))

(ert-deftest p3-config-platform-setup-preserves-subsystem-timing ()
  (with-temp-buffer
    (insert-file-contents (expand-file-name "config.org" p3-config-test--root))
    (goto-char (point-min))
    (should-not (search-forward "(p3/platform-setup)" nil t))
    (goto-char (point-min))
    (let ((rtools-position
           (progn
             (should (search-forward "(p3/windows-configure-rtools)" nil t))
             (point)))
          ess-position
          r-position
          terminal-position
          shell-position
          shell-binding-position)
      (setq ess-position
            (progn
              (should (search-forward "(use-package ess-r-mode" nil t))
              (point)))
      (setq r-position
            (progn
              (should (search-forward "(p3/windows-configure-r-program)" nil t))
              (point)))
      (setq terminal-position
            (progn
              (should (search-forward "(use-package p3-terminal" nil t))
              (point)))
      (setq shell-position
            (progn
              (should (search-forward "(p3/windows-configure-shell)" nil t))
              (point)))
      (setq shell-binding-position
            (progn
              (should
               (search-forward
                "(global-set-key (kbd \"C-x C-u\") #'shell)" nil t))
              (point)))
      (should (< rtools-position ess-position))
      (should (< ess-position r-position))
      (should (< r-position terminal-position))
      (should (< terminal-position shell-position))
      (should (< shell-position shell-binding-position)))))

(ert-deftest p3-init-loads-project-and-loader-before-literate-config ()
  (with-temp-buffer
    (insert-file-contents (expand-file-name "init.el" p3-config-test--root))
    (let ((load-path-position
           (progn
             (should (search-forward "(add-to-list 'load-path p3/lisp-directory)" nil t))
             (point)))
          project-position
          loader-position
          config-position)
      (setq project-position
            (progn
              (should (search-forward "(require 'p3-project)" nil t))
              (point)))
      (setq loader-position
            (progn
              (should (search-forward "(require 'p3-config-loader)" nil t))
              (point)))
      (setq config-position
            (progn
              (should (search-forward "(p3/config-load)" nil t))
              (point)))
      (should (< load-path-position project-position))
      (should (< project-position loader-position))
      (should (< loader-position config-position)))))

(ert-deftest p3-init-does-not-unconditionally-load-org-for-tangling ()
  (with-temp-buffer
    (insert-file-contents (expand-file-name "init.el" p3-config-test--root))
    (should-not (search-forward "(require 'ob-tangle)" nil t))
    (goto-char (point-min))
    (should-not (search-forward "(org-babel-tangle-file" nil t))
    (goto-char (point-min))
    (should-not (search-forward "(defun p3/load-config" nil t))))

(ert-deftest p3-init-does-not-special-case-org-export ()
  (with-temp-buffer
    (insert-file-contents (expand-file-name "init.el" p3-config-test--root))
    (should-not (search-forward "(load \"p3-org-export\"" nil t))))

(provide 'p3-config-test)

;;; p3-config-test.el ends here
