;;; p3-config-python-test.el --- Python configuration boundary tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'seq)

(defconst p3-config-python-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(defun p3-config-python-test--path (relative)
  "Return RELATIVE under the repository root."
  (expand-file-name relative p3-config-python-test--root))

(defun p3-config-python-test--contents (relative)
  "Return contents of repository file RELATIVE."
  (with-temp-buffer
    (insert-file-contents (p3-config-python-test--path relative))
    (buffer-string)))

(defun p3-config-python-test--forms (relative)
  "Read all top-level Lisp forms from RELATIVE."
  (with-temp-buffer
    (insert-file-contents (p3-config-python-test--path relative))
    (goto-char (point-min))
    (let (forms)
      (condition-case nil
          (while t
            (push (read (current-buffer)) forms))
        (end-of-file nil))
      (nreverse forms))))

(defun p3-config-python-test--find-top-level (relative predicate)
  "Return first top-level form in RELATIVE matching PREDICATE."
  (seq-find predicate (p3-config-python-test--forms relative)))

(defun p3-config-python-test--use-package-form (package)
  "Return the `use-package' form for PACKAGE in the Python config module."
  (p3-config-python-test--find-top-level
   "lisp/p3-config-python.el"
   (lambda (form)
     (and (consp form)
          (eq (car form) 'use-package)
          (eq (cadr form) package)))))

(defun p3-config-python-test--keyword-values (form keyword)
  "Return all FORM values following KEYWORD up to the next keyword."
  (let ((tail (memq keyword (cddr form)))
        values)
    (should tail)
    (setq tail (cdr tail))
    (while (and tail (not (keywordp (car tail))))
      (push (car tail) values)
      (setq tail (cdr tail)))
    (nreverse values)))

(defun p3-config-python-test--function-symbol (value)
  "Normalize VALUE from `#\='symbol' syntax to SYMBOL."
  (if (and (consp value)
           (eq (car value) 'function)
           (symbolp (cadr value)))
      (cadr value)
    value))

(defun p3-config-python-test--python-bindings ()
  "Return normalized source bindings for `python-mode'."
  (let* ((form (p3-config-python-test--use-package-form 'python))
         (bind-section
          (car (p3-config-python-test--keyword-values form :bind))))
    (should (equal (seq-take bind-section 2) '(:map python-mode-map)))
    (mapcar
     (lambda (binding)
       (cons (car binding)
             (p3-config-python-test--function-symbol (cdr binding))))
     (cddr bind-section))))

(defun p3-config-python-test--python-hooks ()
  "Return normalized hook functions configured for `python-mode'."
  (let* ((form (p3-config-python-test--use-package-form 'python))
         (hook-section
          (car (p3-config-python-test--keyword-values form :hook))))
    (mapcar
     (lambda (entry)
       (cons (car entry)
             (p3-config-python-test--function-symbol (cdr entry))))
     hook-section)))

(defun p3-config-python-test--ts-form ()
  "Return the top-level conditional configuring `python-ts-mode'."
  (p3-config-python-test--find-top-level
   "lisp/p3-config-python.el"
   (lambda (form)
     (and (consp form)
          (eq (car form) 'when)
          (equal (cadr form) '(fboundp 'python-ts-mode))))))

(defun p3-config-python-test--ts-hooks ()
  "Return normalized hook functions configured for `python-ts-mode'."
  (let ((form (p3-config-python-test--ts-form)))
    (mapcar
     (lambda (entry)
       (cons 'python-mode
             (p3-config-python-test--function-symbol (nth 2 entry))))
     (seq-filter
      (lambda (entry)
        (and (consp entry)
             (eq (car entry) 'add-hook)
             (eq (cadr entry) 'python-ts-mode-hook)))
      (cddr form)))))

(defun p3-config-python-test--ts-bindings ()
  "Return normalized source bindings for `python-ts-mode'."
  (let* ((form (p3-config-python-test--ts-form))
         (after-load
          (seq-find
           (lambda (entry)
             (and (consp entry)
                  (eq (car entry) 'with-eval-after-load)
                  (eq (cadr entry) 'python)))
           (cddr form))))
    (mapcar
     (lambda (entry)
       (cons (cadr (nth 2 entry))
             (p3-config-python-test--function-symbol (nth 3 entry))))
     (cddr after-load))))

(ert-deftest p3-config-python-loads-behavior-owner-explicitly ()
  (let* ((forms (p3-config-python-test--forms "lisp/p3-config-python.el"))
         (loader-position
          (seq-position forms '(require 'p3-config-loader) #'equal))
         (behavior-position
          (seq-position forms '(p3/config-load-module 'p3-python) #'equal)))
    (should (integerp loader-position))
    (should (integerp behavior-position))
    (should (< loader-position behavior-position))))

(ert-deftest p3-config-python-preserves-python-mode-wiring ()
  (should
   (equal
    (p3-config-python-test--python-bindings)
    '(("C-<return>")
      ("S-<return>" . python-shell-send-statement)
      ("C-c C-c" . p3/python-send-region-or-paragraph-and-step)
      ("C-<up>" . backward-paragraph)
      ("C-<down>" . forward-paragraph)
      ("C-c C-z" . p3/python-display-shell))))
  (should
   (equal
    (p3-config-python-test--python-hooks)
    '((python-mode . p3/python-setup-project-interpreter)
      (python-mode . p3/python-eglot-ensure)
      (python-mode . p3/python-disable-flycheck)))))

(ert-deftest p3-config-python-preserves-python-custom-values ()
  (let ((custom-values
         (p3-config-python-test--keyword-values
          (p3-config-python-test--use-package-form 'python)
          :custom)))
    (should
     (equal
      custom-values
      '((python-indent-guess-indent-offset t)
        (python-indent-guess-indent-offset-verbose nil)
        (python-shell-interpreter
         (if (eq system-type 'windows-nt) "python" "python3"))
        (python-shell-interpreter-args "-i"))))))

(ert-deftest p3-config-python-preserves-python-ts-mode-wiring ()
  (should
   (equal
    (p3-config-python-test--ts-form)
    '(when (fboundp 'python-ts-mode)
       (add-to-list 'auto-mode-alist '("\\.py\\'" . python-ts-mode))
       (add-hook 'python-ts-mode-hook #'p3/python-setup-project-interpreter)
       (add-hook 'python-ts-mode-hook #'p3/python-eglot-ensure)
       (add-hook 'python-ts-mode-hook #'p3/python-disable-flycheck)
       (with-eval-after-load 'python
         (define-key python-ts-mode-map (kbd "C-<return>") nil)
         (define-key python-ts-mode-map (kbd "S-<return>")
           #'python-shell-send-statement)
         (define-key python-ts-mode-map (kbd "C-c C-c")
           #'p3/python-send-region-or-paragraph-and-step)
         (define-key python-ts-mode-map (kbd "C-<up>") #'backward-paragraph)
         (define-key python-ts-mode-map (kbd "C-<down>") #'forward-paragraph)
         (define-key python-ts-mode-map (kbd "C-c C-z")
           #'p3/python-display-shell))))))

(ert-deftest p3-config-python-mode-wiring-remains-symmetric ()
  (should (equal (p3-config-python-test--ts-hooks)
                 (p3-config-python-test--python-hooks)))
  (should (equal (p3-config-python-test--ts-bindings)
                 (p3-config-python-test--python-bindings))))

(ert-deftest p3-config-python-preserves-eglot-bindings ()
  (let* ((form (p3-config-python-test--use-package-form 'eglot))
         (bind-section
          (car (p3-config-python-test--keyword-values form :bind))))
    (should
     (equal
      bind-section
      '(:map eglot-mode-map
        ("C-c l r" . eglot-rename)
        ("C-c l a" . eglot-code-actions)
        ("C-c l f" . eglot-format))))))

(ert-deftest p3-config-python-owns-flake8-executable ()
  (should
   (member
    '(setq flycheck-python-flake8-executable "flake8")
    (p3-config-python-test--forms "lisp/p3-config-python.el"))))

(provide 'p3-config-python-test)

;;; p3-config-python-test.el ends here
