;;; p3-config-editing-ownership-test.el --- Editing ownership regressions -*- lexical-binding: t; -*-

(require 'ert)

(defconst p3-config-editing-ownership-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name)))))

(defun p3-config-editing-ownership-test--contents (relative)
  (with-temp-buffer
    (insert-file-contents
     (expand-file-name relative p3-config-editing-ownership-test--root))
    (buffer-string)))

(ert-deftest p3-config-editing-owns-generic-editing-packages ()
  (let ((config (p3-config-editing-ownership-test--contents "config.org"))
        (editing
         (p3-config-editing-ownership-test--contents
          "lisp/p3-config-editing.el")))
    (dolist (package '(synosaurus yasnippet flycheck rainbow-mode ispell))
      (let ((form (format "(use-package %s" package)))
        (should (string-match-p (regexp-quote form) editing))
        (should-not (string-match-p (regexp-quote form) config))))))

(ert-deftest p3-config-editing-preserves-moved-package-settings ()
  (let ((editing
         (p3-config-editing-ownership-test--contents
          "lisp/p3-config-editing.el")))
    (dolist (setting
             '("(synosaurus-mode)"
               "(setq synosaurus-choose-method 'popup)"
               "(yas-global-mode 1)"
               "(add-to-list 'yas-snippet-dirs \"~/.emacs.d/snippets\")"
               "(after-init . global-flycheck-mode)"
               "flycheck-global-modes '(not LaTeX-mode latex-mode org-mode)"
               "flycheck-checker-error-threshold 1000"
               "(add-hook 'prog-mode-hook #'rainbow-mode)"
               "(eq system-type 'windows-nt)"
               "p3/windows-hunspell-program"
               "p3/windows-hunspell-dictionary-directory"
               "(setenv \"DICTIONARY\" \"en_US\")"
               "(eq system-type 'gnu/linux)"
               "(setq ispell-program-name \"hunspell\")"
               "ispell-local-dictionary \"en_US\""
               "ispell-dictionary \"english\""))
      (should (string-match-p (regexp-quote setting) editing)))))

(ert-deftest p3-config-editing-remains-early-owner ()
  (let* ((config (p3-config-editing-ownership-test--contents "config.org"))
         (editing
          (string-match
           (regexp-quote "(p3/config-load-module 'p3-config-editing)") config))
         (completion
          (string-match
           (regexp-quote "(p3/config-load-module 'p3-config-completion)") config))
         (python
          (string-match
           (regexp-quote "(p3/config-load-module 'p3-config-python)") config))
         (terminal
          (string-match
           (regexp-quote "(p3/config-load-module 'p3-config-terminal)") config)))
    (should editing)
    (should completion)
    (should python)
    (should terminal)
    (should (< editing completion))
    (should (< editing python))
    (should (< editing terminal))))

(provide 'p3-config-editing-ownership-test)

;;; p3-config-editing-ownership-test.el ends here
