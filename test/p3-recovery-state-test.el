;;; p3-recovery-state-test.el --- Recovery-state path tests -*- lexical-binding: t; -*-

(require 'ert)

(defconst p3-recovery-state-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-recovery-state-test--root))

(require 'p3-core)

(defun p3-recovery-state-test--emacs-program ()
  "Return the current Emacs executable for isolated runtime checks."
  (expand-file-name invocation-name invocation-directory))

(defun p3-recovery-state-test--runtime-form ()
  "Return the child-Emacs form that verifies recovery configuration behavior."
  `(progn
     (setq user-emacs-directory
           ,(file-name-as-directory p3-recovery-state-test--root))
     (add-to-list 'load-path
                  ,(expand-file-name "lisp" p3-recovery-state-test--root))
     (require 'use-package-ensure)
     (setq use-package-ensure-function (lambda (&rest _) t)
           recentf-save-file (expand-file-name "recentf" (getenv "HOME"))
           save-place-file (expand-file-name "places" (getenv "HOME"))
           custom-file (expand-file-name "custom.el" (getenv "HOME")))

     ;; Make undo-tree available without depending on the external package.
     ;; The stub records the configuration at the exact moment global mode is
     ;; enabled, so the test verifies ordering as behavior rather than text.
     (defvar p3/recovery-test-undo-observation nil)
     (defvar undo-tree-auto-save-history nil)
     (defvar undo-tree-history-directory-alist nil)
     (defun global-undo-tree-mode (&optional _arg)
       (let ((undo-dir
              (cdr (assoc "." undo-tree-history-directory-alist))))
         (setq p3/recovery-test-undo-observation
               (list undo-tree-auto-save-history
                     (copy-tree undo-tree-history-directory-alist)
                     (and undo-dir (file-directory-p undo-dir))))))
     (provide 'undo-tree)

     (load-file
      ,(expand-file-name "lisp/p3-config-base.el"
                         p3-recovery-state-test--root))
     (load-file
      ,(expand-file-name "lisp/p3-config-editing.el"
                         p3-recovery-state-test--root))

     (let* ((platform-root
             (if (eq system-type 'windows-nt)
                 (getenv "LOCALAPPDATA")
               (getenv "XDG_STATE_HOME")))
            (state-leaf
             (if (eq system-type 'windows-nt) "Emacs" "emacs"))
            (expected-state-dir
             (file-name-as-directory
              (expand-file-name state-leaf platform-root)))
            (state-dir (p3/state-directory))
            (backup-dir (expand-file-name "backups/" state-dir))
            (undo-dir (expand-file-name "undo/" state-dir))
            (auto-saves-dir "~/.cache/tmp/emacs/auto-saves/"))
       (unless
           (and
            (equal state-dir expected-state-dir)
            (equal backup-directory-alist `(("." . ,backup-dir)))
            (equal tramp-backup-directory-alist
                   `((".*" . ,backup-dir)))
            (equal auto-save-file-name-transforms
                   `((".*" ,auto-saves-dir t)))
            (equal tramp-auto-save-directory auto-saves-dir)
            (file-directory-p backup-dir)
            (file-directory-p (expand-file-name auto-saves-dir))
            backup-by-copying
            delete-old-versions
            version-control
            (= kept-new-versions 5)
            (= kept-old-versions 2)
            undo-tree-auto-save-history
            (equal undo-tree-history-directory-alist
                   `(("." . ,undo-dir)))
            (file-directory-p undo-dir)
            (equal p3/recovery-test-undo-observation
                   (list t `(("." . ,undo-dir)) t)))
         (princ
          (format
           (concat
            "Recovery runtime contract failed:\n"
            " state=%S expected=%S\n"
            " backups=%S tramp-backups=%S\n"
            " auto=%S tramp-auto=%S\n"
            " undo=%S enabled=%S observation=%S\n")
           state-dir expected-state-dir
           backup-directory-alist tramp-backup-directory-alist
           auto-save-file-name-transforms tramp-auto-save-directory
           undo-tree-history-directory-alist undo-tree-auto-save-history
           p3/recovery-test-undo-observation))
         (kill-emacs 1)))
     (kill-emacs 0)))

(defun p3-recovery-state-test--run-runtime-contract ()
  "Verify recovery configuration in a child Emacs using only temporary state."
  (let* ((sandbox (make-temp-file "p3-recovery-state-" t))
         (home-dir (expand-file-name "home/" sandbox))
         (xdg-state-dir (expand-file-name "xdg-state/" sandbox))
         (local-appdata-dir (expand-file-name "local-appdata/" sandbox))
         (process-environment (copy-sequence process-environment))
         (default-directory p3-recovery-state-test--root))
    (unwind-protect
        (progn
          (dolist (dir (list home-dir xdg-state-dir local-appdata-dir))
            (make-directory dir t))
          (setenv "HOME" (directory-file-name home-dir))
          (setenv "USERPROFILE" (directory-file-name home-dir))
          (setenv "XDG_STATE_HOME" (directory-file-name xdg-state-dir))
          (setenv "LOCALAPPDATA" (directory-file-name local-appdata-dir))
          (with-temp-buffer
            (let ((status
                   (call-process
                    (p3-recovery-state-test--emacs-program)
                    nil t nil
                    "-Q" "--batch" "-L" "lisp"
                    "--eval"
                    (prin1-to-string
                     (p3-recovery-state-test--runtime-form)))))
              (unless (eq status 0)
                (ert-fail
                 (format "Child Emacs exited %S:\n%s"
                         status
                         (buffer-string)))))))
      (delete-directory sandbox t))))

(ert-deftest p3-state-directory-linux-respects-xdg-state-home ()
  (let ((system-type 'gnu/linux)
        (process-environment (copy-sequence process-environment)))
    (setenv "XDG_STATE_HOME" "/tmp/p3-state-root")
    (should
     (equal (p3/state-directory)
            (file-name-as-directory
             (expand-file-name "emacs" "/tmp/p3-state-root"))))))

(ert-deftest p3-state-directory-linux-falls-back-under-home ()
  (let ((system-type 'gnu/linux)
        (process-environment (copy-sequence process-environment)))
    (setenv "XDG_STATE_HOME" nil)
    (should
     (equal (p3/state-directory)
            (file-name-as-directory
             (expand-file-name "~/.local/state/emacs/"))))))

(ert-deftest p3-state-directory-windows-respects-localappdata ()
  (let ((system-type 'windows-nt)
        (process-environment (copy-sequence process-environment)))
    (setenv "LOCALAPPDATA" "C:/p3-test/AppData/Local")
    (should
     (equal (p3/state-directory)
            (file-name-as-directory
             (expand-file-name "Emacs" "C:/p3-test/AppData/Local"))))))

(ert-deftest p3-state-directory-windows-falls-back-under-home ()
  (let ((system-type 'windows-nt)
        (process-environment (copy-sequence process-environment)))
    (setenv "LOCALAPPDATA" nil)
    (should
     (equal (p3/state-directory)
            (file-name-as-directory
             (expand-file-name "~/.local/state/emacs/"))))))

(ert-deftest p3-recovery-state-runtime-contract-is-behavioral-and-isolated ()
  (p3-recovery-state-test--run-runtime-contract))

(provide 'p3-recovery-state-test)

;;; p3-recovery-state-test.el ends here
