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

(load-file
 (expand-file-name "lisp/p3-config-editing.el"
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

(provide 'p3-config-editing-windows-test)

;;; p3-config-editing-windows-test.el ends here
