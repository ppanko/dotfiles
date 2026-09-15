;;; p3-config-editing-windows-test.el --- Windows editing config tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'use-package-ensure)

(defvar p3/windows-hunspell-program)
(defvar p3/windows-hunspell-dictionary-directory)
(defvar ispell-program-name)
(defvar ispell-local-dictionary)
(defvar ispell-dictionary)
(defvar ispell-local-dictionary-alist)

(defconst p3-config-editing-windows-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(add-to-list 'load-path
             (expand-file-name "lisp" p3-config-editing-windows-test--root))

;; The test exercises configuration behavior, not package installation.
(setq use-package-ensure-function (lambda (&rest _) t))

;; Loading the owner can execute undo-tree's :config when the package exists
;; on a developer machine.  Redirect durable state before loading so that test
;; discovery can never create %LOCALAPPDATA%/Emacs/undo/ in the real profile.
(defconst p3-config-editing-windows-test--state-root
  (make-temp-file "p3-config-editing-windows-state-" t))

(let ((process-environment (copy-sequence process-environment))
      (test-home
       (expand-file-name "home/" p3-config-editing-windows-test--state-root)))
  (make-directory test-home t)
  (setenv "HOME" (directory-file-name test-home))
  (setenv "USERPROFILE" (directory-file-name test-home))
  (setenv "LOCALAPPDATA"
          (directory-file-name p3-config-editing-windows-test--state-root))
  (setenv "XDG_STATE_HOME"
          (directory-file-name p3-config-editing-windows-test--state-root))
  (load-file
   (expand-file-name "lisp/p3-config-editing.el"
                     p3-config-editing-windows-test--root)))

(load-file
 (expand-file-name "test/p3-recovery-state-test.el"
                   p3-config-editing-windows-test--root))

;; smartparens is intentionally absent from the bare CI Emacs.  Loading the
;; owner still installs its hook, so remove that unrelated hook before ERT
;; creates diagnostic Emacs Lisp buffers.
(remove-hook 'prog-mode-hook #'smartparens-mode)

(ert-deftest p3-config-editing-windows-spelling-uses-rtools-hunspell ()
  "Spelling setup should consume the Hunspell paths discovered by Rtools."
  (skip-unless (eq system-type 'windows-nt))
  (require 'ispell)
  (let ((program "C:/p3-test/hunspell.exe")
        (dictionary-directory "C:/p3-test/hunspell")
        (old-dictpath (getenv "DICTPATH"))
        (old-dictionary (getenv "DICTIONARY")))
    (unwind-protect
        (let ((p3/windows-hunspell-program program)
              (p3/windows-hunspell-dictionary-directory dictionary-directory)
              (ispell-program-name nil)
              (ispell-local-dictionary nil)
              (ispell-dictionary nil)
              (ispell-local-dictionary-alist nil))
          (p3/config-editing-setup-spelling)
          (should (equal ispell-program-name program))
          (should (equal (getenv "DICTPATH") dictionary-directory))
          (should (equal (getenv "DICTIONARY") "en_US"))
          (should (equal ispell-local-dictionary "en_US"))
          (should (equal ispell-dictionary "english"))
          (should
           (equal ispell-local-dictionary-alist
                  '(("en_US" "[[:alpha:]]" "[^[:alpha:]]" "[']" nil
                     ("-d" "en_US") nil utf-8)))))
      (setenv "DICTPATH" old-dictpath)
      (setenv "DICTIONARY" old-dictionary))))

(ert-deftest p3-config-editing-windows-refresh-spelling-follows-rtools-change ()
  "Refresh should move and clear spelling state owned by Rtools discovery."
  (skip-unless (eq system-type 'windows-nt))
  (require 'ispell)
  (let ((old-program "C:/rtools45/usr/bin/hunspell.exe")
        (old-dictionary-directory "C:/rtools45/usr/share/hunspell")
        (new-program "C:/rtools46/usr/bin/hunspell.exe")
        (new-dictionary-directory "C:/rtools46/usr/share/hunspell")
        (old-dictpath (getenv "DICTPATH")))
    (unwind-protect
        (let ((p3/windows-hunspell-program new-program)
              (p3/windows-hunspell-dictionary-directory
               new-dictionary-directory)
              (p3/config-editing--windows-hunspell-program old-program)
              (p3/config-editing--windows-hunspell-dictionary-directory
               old-dictionary-directory)
              (ispell-program-name old-program))
          (setenv "DICTPATH" old-dictionary-directory)
          (should (fboundp 'p3/config-editing-refresh-spelling))
          (p3/config-editing-refresh-spelling)
          (should (equal ispell-program-name new-program))
          (should (equal (getenv "DICTPATH") new-dictionary-directory))
          (setq p3/windows-hunspell-program nil
                p3/windows-hunspell-dictionary-directory nil)
          (p3/config-editing-refresh-spelling)
          (should-not ispell-program-name)
          (should-not (getenv "DICTPATH")))
      (setenv "DICTPATH" old-dictpath))))

(provide 'p3-config-editing-windows-test)

;;; p3-config-editing-windows-test.el ends here
