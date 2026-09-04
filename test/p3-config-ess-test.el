;;; p3-config-ess-test.el --- ESS configuration boundary tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'seq)

(defconst p3-config-ess-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(defun p3-config-ess-test--path (relative)
  "Return RELATIVE under the repository root."
  (expand-file-name relative p3-config-ess-test--root))

(defun p3-config-ess-test--contents (relative)
  "Return contents of repository file RELATIVE."
  (with-temp-buffer
    (insert-file-contents (p3-config-ess-test--path relative))
    (buffer-string)))

(defun p3-config-ess-test--forms (relative)
  "Read all top-level Lisp forms from RELATIVE."
  (with-temp-buffer
    (insert-file-contents (p3-config-ess-test--path relative))
    (goto-char (point-min))
    (let (forms)
      (condition-case nil
          (while t
            (push (read (current-buffer)) forms))
        (end-of-file nil))
      (nreverse forms))))

(defun p3-config-ess-test--find-top-level (relative predicate)
  "Return first top-level form in RELATIVE matching PREDICATE."
  (seq-find predicate (p3-config-ess-test--forms relative)))

(defun p3-config-ess-test--use-package-form ()
  "Return the `use-package ess-r-mode' form under test."
  (p3-config-ess-test--find-top-level
   "lisp/p3-config-ess.el"
   (lambda (form)
     (and (consp form)
          (eq (car form) 'use-package)
          (eq (cadr form) 'ess-r-mode)))))

(defun p3-config-ess-test--defvar-form (symbol)
  "Return top-level defvar for SYMBOL in the ESS config module."
  (p3-config-ess-test--find-top-level
   "lisp/p3-config-ess.el"
   (lambda (form)
     (and (consp form)
          (eq (car form) 'defvar)
          (eq (cadr form) symbol)))))

(defun p3-config-ess-test--defun-form (symbol)
  "Return top-level defun for SYMBOL in the ESS config module."
  (p3-config-ess-test--find-top-level
   "lisp/p3-config-ess.el"
   (lambda (form)
     (and (consp form)
          (eq (car form) 'defun)
          (eq (cadr form) symbol)))))

(defun p3-config-ess-test--setq-pairs ()
  "Return variable/value pairs from the ESS package `setq' form."
  (let* ((form (p3-config-ess-test--use-package-form))
         (setq-form (plist-get (cddr form) :config)))
    (should (eq (car-safe setq-form) 'setq))
    (seq-partition (cdr setq-form) 2)))

(ert-deftest p3-config-ess-load-order-is-explicit ()
  (let ((forms (p3-config-ess-test--forms "lisp/p3-config-ess.el")))
    (should (member '(require 'p3-config-loader) forms))
    (should (member '(p3/config-load-module 'p3-ess) forms))
    (should (member '(p3/ess-setup) forms))
    (should (member '(p3/config-load-module 'p3-r-tools) forms))
    (should (member '(keymap-global-set "C-c R" p3-r-command-map) forms))))

(ert-deftest p3-config-ess-preserves-company-backends-exactly ()
  (should
   (equal
    (nth 2 (p3-config-ess-test--defvar-form 'p3/r-company-backends))
    '(quote
      ((:separate
        company-R-library company-R-args company-R-objects
        company-dabbrev-code
        :with company-yasnippet)
       company-capf)))))

(ert-deftest p3-config-ess-preserves-company-buffer-hook ()
  (should
   (equal
    (cddddr (p3-config-ess-test--defun-form 'p3/ess-company-config))
    '((setq-local company-backends p3/r-company-backends)))))

(ert-deftest p3-config-ess-preserves-inferior-buffer-setup ()
  (should
   (equal
    (cddddr (p3-config-ess-test--defun-form 'p3/ess-inferior-mode-setup))
    '((setq-local ansi-color-for-comint-mode 'filter)
      (smartparens-mode 1)))))

(ert-deftest p3-config-ess-preserves-hooks-and-bindings ()
  (let* ((form (p3-config-ess-test--use-package-form))
         (args (cddr form)))
    (should form)
    (should
     (equal
      (plist-get args :hook)
      '((inferior-ess-mode . p3/ess-inferior-mode-setup)
        (ess-r-post-run . p3-r-load-view-data-frame)
        (ess-r-mode . p3/ess-company-config)
        (ess-r-mode . p3/use-project-root-as-default-dir)
        (ess-mode . (lambda () (modify-syntax-entry ?_ "w"))))))
    (should
     (equal
      (plist-get args :bind)
      '(:map ess-mode-map
        ("C-<return>" . nil)
        ("S-<return>" . ess-eval-region-or-line-visibly-and-step)
        ("C-." . p3-r-insert-pipe)
        ("C-c i" . p3-r-evaluate-library-section)
        ("C-c v" . p3-r-view-data-frame-at-point)
        ("C-c m" . p3-r-targets-make)
        ("C-c d" . p3-r-targets-make-debug)
        ("C-c l" . p3-r-targets-load-at-point)
        :map inferior-ess-r-mode-map
        ("C-c v" . p3-r-view-data-frame-at-point)
        ("C-c m" . p3-r-targets-make)
        ("C-c d" . p3-r-targets-make-debug)
        ("C-c l" . p3-r-targets-load-at-point))))))

(ert-deftest p3-config-ess-preserves-sensitive-settings ()
  (let ((pairs (p3-config-ess-test--setq-pairs)))
    (dolist (pair
             '((ess-ask-for-ess-directory nil)
               (ess-style 'RStudio)
               (ess-eval-visibly t)
               (ess-toggle-underscore nil)
               (ess-use-flymake nil)
               (ess--command-default-timeout 1)
               (inferior-R-args "--no-save")
               (ess-gen-proc-buffer-name-function
                'ess-gen-proc-buffer-name:project-or-directory)))
      (should (member pair pairs)))
    (should
     (member
      '(flycheck-lintr-linters
        "linters_with_defaults(object_name_linter(c('snake_case','camelCase')), commented_code_linter = NULL, line_length_linter(90), single_quotes_linter=NULL)")
      pairs))
    (should
     (member
      '(ess-R-font-lock-keywords
        '((ess-R-fl-keyword:modifiers . t)
          (ess-R-fl-keyword:fun-defs . t)
          (ess-R-fl-keyword:keywords . t)
          (ess-R-fl-keyword:assign-ops)
          (ess-R-fl-keyword:constants . t)
          (ess-fl-keyword:fun-calls . t)
          (ess-fl-keyword:numbers . t)
          (ess-fl-keyword:operators . t)
          (ess-fl-keyword:delimiters . t)
          (ess-fl-keyword:= . t)
          (ess-R-fl-keyword:F&T . t)
          (ess-R-fl-keyword:%op% . t)))
      pairs))))

(ert-deftest p3-config-ess-preserves-rmarkdown-compile-hook ()
  (let ((forms (p3-config-ess-test--forms "lisp/p3-config-ess.el")))
    (should
     (equal
      (p3-config-ess-test--defun-form 'compile-rmd)
      '(defun compile-rmd ()
         (set (make-local-variable 'compile-command)
              (concat "R -e \"rmarkdown::render('"
                      buffer-file-name
                      "')\"")))))
    (should (member '(add-hook 'ess-mode-hook 'compile-rmd) forms))
    (should (member '(add-hook 'markdown-mode-hook 'compile-rmd) forms))))

(ert-deftest p3-ess-library-has-no-buffer-configuration-glue ()
  (let ((contents (p3-config-ess-test--contents "lisp/p3-ess.el")))
    (dolist (forbidden '("p3/ess-inferior-mode-setup"
                         "ansi-color-for-comint-mode"
                         "smartparens-mode"))
      (should-not (string-match-p (regexp-quote forbidden) contents)))))

(ert-deftest p3-generic-completion-has-no-ess-company-owner ()
  (let ((contents
         (p3-config-ess-test--contents "lisp/p3-config-completion.el")))
    (dolist (forbidden '("p3/r-company-backends"
                         "p3/ess-company-config"
                         "company-R-library"
                         "company-R-args"
                         "company-R-objects"))
      (should-not (string-match-p (regexp-quote forbidden) contents)))))

(provide 'p3-config-ess-test)

;;; p3-config-ess-test.el ends here
