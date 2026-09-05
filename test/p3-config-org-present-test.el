;;; p3-config-org-present-test.el --- Org presentation config tests -*- lexical-binding: t; -*-

(require 'ert)
(require 'seq)

(defconst p3-config-org-present-test--root
  (file-name-directory
   (directory-file-name
    (file-name-directory (or load-file-name buffer-file-name))))
  "Root of the Emacs configuration under test.")

(defun p3-config-org-present-test--path (relative)
  "Return RELATIVE under the repository root."
  (expand-file-name relative p3-config-org-present-test--root))

(defun p3-config-org-present-test--contents (relative)
  "Return contents of repository file RELATIVE."
  (with-temp-buffer
    (insert-file-contents (p3-config-org-present-test--path relative))
    (buffer-string)))

(defun p3-config-org-present-test--forms ()
  "Read all top-level forms from the Org presentation config module."
  (with-temp-buffer
    (insert-file-contents
     (p3-config-org-present-test--path "lisp/p3-config-org-present.el"))
    (goto-char (point-min))
    (let (forms)
      (condition-case nil
          (while t
            (push (read (current-buffer)) forms))
        (end-of-file nil))
      (nreverse forms))))

(defun p3-config-org-present-test--use-package-form (package)
  "Return the top-level `use-package' form for PACKAGE."
  (seq-find
   (lambda (form)
     (and (consp form)
          (eq (car form) 'use-package)
          (eq (cadr form) package)))
   (p3-config-org-present-test--forms)))

(defun p3-config-org-present-test--keyword-values (package keyword)
  "Return values following KEYWORD for PACKAGE."
  (let* ((form (p3-config-org-present-test--use-package-form package))
         (tail (memq keyword (cddr form)))
         values)
    (should tail)
    (setq tail (cdr tail))
    (while (and tail (not (keywordp (car tail))))
      (push (car tail) values)
      (setq tail (cdr tail)))
    (nreverse values)))

(ert-deftest p3-config-org-present-preserves-package-order-and-dependency-owner ()
  (let* ((forms (p3-config-org-present-test--forms))
         (hide (seq-position
                forms (p3-config-org-present-test--use-package-form
                       'hide-mode-line)
                #'equal))
         (fill (seq-position
                forms (p3-config-org-present-test--use-package-form
                       'visual-fill-column)
                #'equal))
         (behavior (seq-position
                    forms '(p3/config-load-module 'p3-org-present) #'equal))
         (present (seq-position
                   forms (p3-config-org-present-test--use-package-form
                          'org-present)
                   #'equal))
         (config-source
          (p3-config-org-present-test--contents
           "lisp/p3-config-org-present.el"))
         (behavior-source
          (p3-config-org-present-test--contents
           "lisp/p3-org-present.el")))
    (should (< hide fill))
    (should (< fill behavior))
    (should (< behavior present))
    (should-not (string-match-p
                 (regexp-quote "(require 'face-remap)")
                 config-source))
    (should (string-match-p
             (regexp-quote "(require 'face-remap)")
             behavior-source))))

(ert-deftest p3-config-org-present-preserves-hide-and-fill-package-wiring ()
  (should
   (equal
    (p3-config-org-present-test--use-package-form 'hide-mode-line)
    '(use-package hide-mode-line
       :after (org-present))))
  (should
   (equal
    (p3-config-org-present-test--use-package-form 'visual-fill-column)
    '(use-package visual-fill-column))))

(ert-deftest p3-config-org-present-preserves-bindings-hooks-and-scale ()
  (should
   (equal
    (p3-config-org-present-test--keyword-values 'org-present :bind)
    '(((:map org-mode-map
             ("C-c P" . p3/org-present-start))
       (:map org-present-mode-keymap
             ("C-c C-j" . p3/org-present-next)
             ("C-c C-k" . p3/org-present-prev)
             ("SPC" . p3/org-present-next)
             ("<backspace>" . p3/org-present-prev)
             ("n" . p3/org-present-next)
             ("p" . p3/org-present-prev)
             ("f" . p3/org-present-toggle-fullscreen)
             ("q" . org-present-quit))))))
  (should
   (equal
    (p3-config-org-present-test--keyword-values 'org-present :hook)
    '(((org-present-mode . p3/org-present-hook)
       (org-present-mode-quit . p3/org-present-quit-hook)))))
  (should
   (equal
    (p3-config-org-present-test--keyword-values 'org-present :config)
    '((setq org-present-text-scale 4)))))

(provide 'p3-config-org-present-test)

;;; p3-config-org-present-test.el ends here
