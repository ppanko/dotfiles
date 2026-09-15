;;; p3-r-eldoc-test.el --- R Eldoc ownership tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'eglot)

(defconst p3-r-eldoc-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(add-to-list 'load-path (expand-file-name "lisp" p3-r-eldoc-test--root))
(require 'p3-r-language-server)

(ert-deftest p3-r-eglot-keeps-hover-as-the-only-r-documentation-provider ()
  (with-temp-buffer
    (setq-local eldoc-documentation-functions
                '(ess-r-eldoc-function
                  eglot-signature-eldoc-function
                  eglot-hover-eldoc-function
                  p3-r-eldoc-test--other-provider))
    (cl-letf (((symbol-function 'eglot-managed-p) (lambda () t)))
      (p3/r-eglot-sync-eldoc-ownership))
    (should-not (memq 'ess-r-eldoc-function eldoc-documentation-functions))
    (should-not (memq 'eglot-signature-eldoc-function
                      eldoc-documentation-functions))
    (should (memq 'eglot-hover-eldoc-function eldoc-documentation-functions))
    (should (memq 'p3-r-eldoc-test--other-provider
                  eldoc-documentation-functions))))

(ert-deftest p3-r-eglot-restores-preexisting-ess-eldoc-on-disconnect ()
  (with-temp-buffer
    (setq-local eldoc-documentation-functions
                '(ess-r-eldoc-function
                  eglot-signature-eldoc-function
                  eglot-hover-eldoc-function))
    (let ((managed t))
      (cl-letf (((symbol-function 'eglot-managed-p)
                 (lambda () managed)))
        (p3/r-eglot-sync-eldoc-ownership)
        ;; `p3/r-eglot-ensure' may call the sync helper after Eglot's own
        ;; managed-mode hook has already done so.  Repeated synchronization
        ;; must not forget that ESS Eldoc existed before Eglot took ownership.
        (p3/r-eglot-sync-eldoc-ownership)
        (should-not (memq 'ess-r-eldoc-function
                          eldoc-documentation-functions))
        (setq managed nil)
        (setq-local eldoc-documentation-functions nil)
        (p3/r-eglot-sync-eldoc-ownership)))
    (should (= (cl-count 'ess-r-eldoc-function
                         eldoc-documentation-functions)
               1))))

(ert-deftest p3-r-eglot-does-not-invent-ess-eldoc-on-disconnect ()
  (with-temp-buffer
    (setq-local eldoc-documentation-functions
                '(eglot-signature-eldoc-function
                  eglot-hover-eldoc-function))
    (let ((managed t))
      (cl-letf (((symbol-function 'eglot-managed-p)
                 (lambda () managed)))
        (p3/r-eglot-sync-eldoc-ownership)
        (setq managed nil)
        (setq-local eldoc-documentation-functions nil)
        (p3/r-eglot-sync-eldoc-ownership)))
    (should-not (memq 'ess-r-eldoc-function eldoc-documentation-functions))))

(ert-deftest p3-r-eglot-leaves-ess-eldoc-when-eglot-does-not-own-eldoc ()
  (with-temp-buffer
    (setq-local eldoc-documentation-functions
                '(ess-r-eldoc-function p3-r-eldoc-test--other-provider))
    (cl-letf (((symbol-function 'eglot-managed-p) (lambda () t)))
      (p3/r-eglot-sync-eldoc-ownership))
    (should (memq 'ess-r-eldoc-function eldoc-documentation-functions))
    (should (memq 'p3-r-eldoc-test--other-provider
                  eldoc-documentation-functions))))

(ert-deftest p3-r-eglot-installs-buffer-local-eldoc-ownership-hook ()
  (with-temp-buffer
    (setq-local eldoc-documentation-functions '(ess-r-eldoc-function))
    (setq-local eglot-managed-mode-hook nil)
    (let ((eglot-stay-out-of nil)
          (eglot-ignored-server-capabilities nil)
          (eglot-server-programs nil)
          called)
      (cl-letf (((symbol-function 'p3/r-language-server-command)
                 (lambda () '("managed-R" "--slave" "-e" "managed")))
                ((symbol-function 'eglot-ensure)
                 (lambda () (setq called t)))
                ((symbol-function 'eglot-managed-p)
                 (lambda () nil)))
        (p3/r-eglot-ensure))
      (should called)
      (should (local-variable-p 'eglot-managed-mode-hook))
      (should (memq #'p3/r-eglot-sync-eldoc-ownership
                    eglot-managed-mode-hook))
      (should-not (memq :hoverProvider eglot-ignored-server-capabilities))
      (should-not (memq :signatureHelpProvider
                        eglot-ignored-server-capabilities)))))

(provide 'p3-r-eldoc-test)

;;; p3-r-eldoc-test.el ends here
